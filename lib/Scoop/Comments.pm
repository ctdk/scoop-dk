package Scoop;
use strict;
my $DEBUG = 0;

use Time::HiRes qw(gettimeofday);

use 5.8.0;		# need 'use constant' construct

#
# Index values for comment rows returned from the database.
#
use constant {
	IX_COMMENT_sid			=> 0, 
	IX_COMMENT_cid			=> 1,
	IX_COMMENT_pid			=> 2,
	IX_COMMENT_f_date		=> 3,
	IX_COMMENT_mini_date	=> 4,
	IX_COMMENT_hoursposted	=> 5,		# or null
	IX_COMMENT_subject		=> 6,
	IX_COMMENT_comment		=> 7,		# or null
	IX_COMMENT_uid			=> 8,
	IX_COMMENT_points		=> 9,
	IX_COMMENT_numrate		=> 10,
	IX_COMMENT_norate		=> 11,
	IX_COMMENT_pending		=> 12,
	IX_COMMENT_sig_status	=> 13,
	IX_COMMENT_sig			=> 14,
	IX_COMMENT_commentip	=> 15,
	IX_COMMENT_recrate		=> 16,
	IX_COMMENT_trollrate	=> 17,
	IX_COMMENT_raters		=> 18,
	IX_COMMENT_id			=> 19,
	IX_COMMENT_story_id		=> 20,
	IX_COMMENT_mode			=> 21,		# not in the db; set on-the-fly by older code
	IX_COMMENT_depth		=> 22,		# the tree depth of this comment, set by collect_comments
};

# ___________________________________________________________________________


sub comment_dig {
	my $S = shift;

	my $sid = $S->{CGI}->param('sid');
	my $pid = $S->{CGI}->param('pid');
	my $cid = $S->{CGI}->param('cid');
	my $comment_id = $S->cgi->param('id');
	# For some reason, sometimes cids that look like "15#15" sneak through.
	# Better fix that.
	if($cid =~ /#/){
		my $junk;
		($cid, $junk) = split /#/, $cid;
		}
	if($comment_id =~ /#/){
		my $junk;
		($comment_id, $junk) = split /#/, $comment_id;
		}
	my $tool = $S->{CGI}->param('tool');
	my $mode = $S->{CGI}->param('mode');
	my $post = $S->cgi->param('post');
	my $preview = $S->cgi->param('preview');
	my $showrate = $S->{CGI}->param('showrate');
	my $check_comment = $S->{CGI}->param('pending');
	my ($dynamic, $dynamicmode);
	if ($S->{UI}->{VARS}->{allow_dynamic_comment_mode}) {
		$dynamic = ($S->{CGI}->param('op') eq 'dynamic') ? 1 : 0;
		$dynamicmode = $S->{CGI}->param('dynamicmode');
	} else {
		$dynamic = 0;
		$dynamicmode = 0;
	}

	# some variables for use in the plethora of conditionals below
	my $section = $S->_get_story_section($sid);
	my $sect_post_perm;
	my $sect_read_perm;
	# this can be set to true during the perm checking to supress displaying
	# the story title, for security purposes
	my $no_title = 0;

	# make sure you treat it properly if its a poll
	if ($S->_does_poll_exist($sid)) {
		$sect_post_perm = $S->have_perm('poll_post_comments');
		$sect_read_perm = $S->have_perm('poll_read_comments');
	} else {
		$sect_post_perm = $S->have_section_perm('norm_post_comments',$section);
		$sect_read_perm = $S->have_section_perm('norm_read_comments',$section);
	}

	$S->{UI}->{BLOCKS}->{subtitle} = 'Comments %%bars%% ';
	
	# Set variables for the dynamic template, and coerce into dynamic mode
	# if we're in a dynamic page
	if ($S->{UI}->{VARS}->{allow_dynamic_comment_mode} && $dynamic) {
		$S->_setup_dynamic_blocks($sid);
		$S->{UI}->{VARS}->{dynamicmode} = ($dynamicmode? 1 : 0);
		$S->{UI}->{VARS}->{mainpid} = 0; # No longer used
		$mode = 'dynamic';
	}

	my $quoted_sid = $S->dbh->quote($sid);
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'title, displaystatus',
		FROM => 'stories',
		WHERE => qq|sid = $quoted_sid|
	});
	my ($story_title, $story_status) = $sth->fetchrow_array();
	$sth->finish;

	my $delete_confirm;
	if ($tool eq 'delete' && $S->have_perm( 'comment_delete' )) {
		if ($S->{CGI}->param('confirm') eq 'delete') {
			$S->_delete_comment($sid, $cid, $pid);
		} elsif ($S->{CGI}->param('confirm') eq 'deletechild') {
			$S->_delete_comment($sid, $cid, $pid, 1);
		} else {
			$delete_confirm = $S->_confirm_delete_comment($sid, $cid, $tool);
		}
	}
	if ($tool eq 'remove' && $S->have_perm( 'comment_remove' )) {
		if ($S->{CGI}->param('confirm') eq 'delete') {
			$S->_remove_comment($sid, $cid, $pid);
		} else {
			$delete_confirm = $S->_confirm_delete_comment($sid, $cid, $tool);
		}
	}
	
	if ( ($tool eq 'toggle_editorial' || $tool eq 'toggle_normal') && $S->have_perm( 'comment_toggle' )) {
		$S->comment_toggle_pending($sid, $cid, $tool);
	}
	
	if ( $S->{CGI}->param('spellcheck') ) {
		$preview = 'Preview';
		$post = '';
	}

	# Check formkey
	if (($tool eq 'post' && $post || $preview) && !$S->check_formkey()) {
		$S->{UI}->{BLOCKS}->{COMM_ERR} = qq|
		<table cellpadding="1" cellspacing="0" border="0" width="100%">
			<tr><td>%%norm_font%%<font color="FF0000"><b>Form key invalid. This is probably because you clicked 'Post' or 'Preview' more than once. DO NOT HIT 'BACK'! If you're sure you haven't already posted this once, go ahead and post (or preview) from this screen.</b></font>%%norm_font_end%%<p></td></tr>
		</table>|;
		$preview = 'Preview';
		$post = '';
	}

	if ( $tool eq 'post' && $post ) {
		my $err;
		if ($S->have_perm( 'comment_post' ) && !$S->_check_archivestatus($sid)) {

			# Check for editorial/topical
			if ( $S->{CGI}->param('pending') == -1) {
				$err .= qq|
					%%norm_font%%<font color="FF0000"><b>Before posting your comment you must either choose for it to be editorial or topical.</b></font>%%norm_font_end%%<p>|;
				$preview = 'Preview';
				$post = '';
			} 
			
			# Check for subject line
			my $check_subj = $S->{CGI}->param('subject');
			$check_subj =~ s/\&nbsp\;//gi;	# Filter spaces out for the check
			unless ( $check_subj && ($check_subj =~ /\w+/) ) {
				$err .= qq|
					%%norm_font%%<font color="FF0000"><b>Please enter a subject for your comment.</b></font>%%norm_font_end%%<p>|;
				$preview = 'Preview';
				$post = '';
			}

			# Now try to post.
			if ( !$preview ) {
				if (my $new_cid = $S->post_comment()) {
					$cid = $new_cid;
					$mode = 'confirm';
				} else {
					$err .= qq|
						%%norm_font%%<b>Post Failed.</b> |.$S->{DBH}->errstr."%%norm_font_end%%<p>";
					$err .= $S->{DBH}->errstr . "<br />\n" if $S->{DBH}->errstr;
					my $checker_error = $S->html_checker->errors_as_string;
					$err .= $checker_error . "\n" if $checker_error;
					$err .= "%%norm_font_end%%<p>";
					$preview = 'Preview';
					$post = '';
				}
			}
		} else {
			$err .= qq|
				%%norm_font%%<b>Post Failed.</b> |.$S->{DBH}->errstr."%%norm_font_end%%<p>";
			$preview = 'Preview';
			$post = '';
		}


		$err .= $S->{DBH}->errstr . "<br />\n" if $S->{DBH}->errstr;
		my $checker_error = $S->html_checker->errors_as_string;
		$err .= $checker_error . "\n" if $checker_error;
		$err .= "%%norm_font_end%%<p>";

		$S->{UI}->{BLOCKS}->{COMM_ERR} = $err if ($err);
	} 
	
	if ($cid && $cid =~ /\d+/) {
		my $quoted_sid = $S->dbh->quote($sid);
		my $qc = $S->dbh->quote($cid);
		my $qc_id = $S->dbh->quote($comment_id);
		my $where = ($comment_id) ? "id = $qc_id" : qq|cid = $qc AND sid = $quoted_sid|;
		my ($rv, $sth) = $S->db_select({
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT => 'pid',
			FROM => 'comments',
			WHERE => $where
			});
		my $id = $sth->fetchrow;
		$sth->finish;
		$pid = $id;
	} 
	
	# Make sure the mode reflects the current mode, for post_form
	$S->{PARAMS}->{'post'} = $post;
	$S->{PARAMS}->{'preview'} = $preview;
	
	my $page;
	my $keys;

	if ($tool eq 'post' && !$post && $S->have_perm( 'comment_post' ) && $sect_post_perm && !$S->_check_archivestatus($sid) ) {
		$page = $S->{UI}->{BLOCKS}->{commentreply_display};

		if (!$cid) {
			$keys->{'replying_to'} = $S->displaystory($sid);
		} else {
			$keys->{'replying_to'} = $S->display_comments($sid, $pid, 'alone');
		}

		$keys->{'post_form'} = $S->post_form();
	} elsif ($tool eq 'post' && $mode eq 'confirm' && $S->have_perm( 'comment_post' ) && $sect_post_perm && !$S->_check_archivestatus($sid)) {
		$page = $S->{UI}->{BLOCKS}->{comment_posted_display};
		$keys->{'comment_controls'} = $S->comment_controls($sid, 'top');
		if ($S->{UI}->{VARS}->{use_mojo} && $S->{TRUSTLEV} == 0) {
			$keys->{'post_msg'} = $S->{UI}->{BLOCKS}->{untrusted_post_message};
		} else {
			$keys->{'post_msg'} = $S->{UI}->{BLOCKS}->{comment_posted_message};
		}
		
		$keys->{'new_comment'} = $S->display_comments($sid, $pid, 'alone', $cid);
	} elsif (!$S->have_perm('moderate') && ($story_status <= -2)) {
		$page = qq|<p><b>%%norm_font%%Sorry, you don't have permission to see comments in the queue.%%norm_font_end%%</b></p>|;
		$no_title = 1;
	} elsif ( $sect_read_perm ) {
		if ($dynamic && !$dynamicmode) {
			# In collapsed mode, just show the comment counts
			$page = $S->display_comments($sid, $pid, 'collapsed');
		} else {
			# Get all relevant ratings
			my $rate = $S->get_comment_option('ratingchoice');

			my $comments = $S->display_comments($sid, $pid, $mode);

			if ($showrate) {
				$comments .= '%%BOX,show_comment_raters%%';
			}

			if (!$dynamic) {
				$page .= $S->comment_controls($sid, 'top');
			}

			$page .= "<p>$delete_confirm</p>" if $delete_confirm;
			$page .= qq|$comments|;

			#if ($comments && !$dynamic) {
			#	$page .= '<p>';
			#	$page .= $S->comment_controls($sid, 'top');
			#}
		}
	} else {
		if ( $tool eq 'post' && $S->have_section_perm('deny_post_comments', $section )) {
			$page = qq|
				<b>%%norm_font%%You don't have permission to post comments to this section.%%norm_font_end%%</b>|;
		} elsif ( $tool ne 'post' && $S->have_section_perm('deny_read_comments', $section )) {
			$page = qq|
				<b>%%norm_font%%You don't have permission to read comments in this section.%%norm_font_end%%</b>|;
		} else {
			$page = qq|<b>%%norm_font%%Sorry, I couldn't find that story.%%norm_font_end%%</b>|;
		}
		$no_title = 1;
	}

	unless ($no_title) {
		$S->{UI}->{BLOCKS}->{subtitle} .= $story_title;
		$S->{UI}->{BLOCKS}->{subtitle} =~ s/</&lt;/g;
		$S->{UI}->{BLOCKS}->{subtitle} =~ s/>/&gt;/g;
	}

	$page = $S->interpolate($page,$keys);
	# hopefully this is OK...
	$page = $S->{UI}->{BLOCKS}->{comment_div_start} . $page 
. $S->{UI}->{BLOCKS}->{comment_div_end};
	$S->{UI}->{BLOCKS}->{CONTENT} = $page;
	return;
}

sub _setup_dynamic_blocks {							# obsolete
	my $S = shift;
	my $sid = shift;

	my $collapse_symbol = $S->js_quote($S->{UI}->{BLOCKS}->{dynamic_collapse_link});
	my $expand_symbol = $S->js_quote($S->{UI}->{BLOCKS}->{dynamic_expand_link});
	my $loading_symbol = $S->js_quote($S->{UI}->{BLOCKS}->{dynamic_loading_link});
	my $loading_message = $S->js_quote($S->{UI}->{BLOCKS}->{dynamic_loading_message});
	my $rootdir = $S->js_quote($S->{UI}->{VARS}->{rootdir} . '/');
	my $sidesc = $S->js_quote($sid);

	$S->{UI}->{BLOCKS}->{dynamicmode_javascript} = $S->{UI}->{BLOCKS}->{dynamic_js_tag};
	# Sorry about the ugly indentation here, but some less
	# intelligent JS parsers (like Konqueror 2.x's) won't execute
	# JS statements that don't start at the beginning of the line
	$S->{UI}->{BLOCKS}->{dynamicmode_javascript} .= qq|
<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript"><!--
collapse_symbol = '$collapse_symbol';
expand_symbol = '$expand_symbol';
loading_symbol = '$loading_symbol';
loading_message = '$loading_message';
rootdir = '$rootdir';
sid = '$sidesc';
//--></SCRIPT>|;
	$S->{UI}->{BLOCKS}->{dynamicmode_iframe} = qq|<IFRAME WIDTH=0 HEIGHT=0 BORDER=0 STYLE="width:0;height:0;border:0" ID="dynamic" NAME="dynamic" SRC="about:blank"></IFRAME>|;
}

sub _confirm_delete_comment {
	my $S = shift;
	my ($sid, $cid, $tool) = @_;

	return qq~%%norm_font%%To actually delete this comment, <a href="%%rootdir%%/comments/$sid/$cid/$tool?confirm=delete">click here</a>.<br/>To delete all the children of this comment, <a href="%%rootdir%%/comments/$sid/$cid/delete?confirm=deletechild">click here</a>.%%norm_font_end%%~;
}

sub _delete_comment {
	my $S = shift;
	my ($sid, $cid, $pid, $delchild) = @_;
	#my $delchild = shift;
	warn "what are we working with? $sid $cid $pid $delchild\n";
	
	$pid = 0 unless $pid;

	$S->run_hook('comment_delete', $sid, $cid);

	my $q_sid = $S->dbh->quote($sid);
	my $q_cid = $S->dbh->quote($cid);
	my $q_pid = $S->dbh->quote($pid);

	# First, get the uid of comment poster
	# Interestingly, pid isn't coming through for some reason.
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'uid, pid',
		FROM => 'comments',
		WHERE => qq|cid = $q_cid AND sid = $q_sid|});
	
	#my $uid = $sth->fetchrow();
	my $u = $sth->fetchrow_hashref();
	my $uid = $u->{uid};
	$pid = $u->{pid};
	
	# Then delete the comment
	$rv = $S->db_delete({
		ARCHIVE => $S->_check_archivestatus($sid),
		FROM => 'comments',
		WHERE => qq|cid = $q_cid AND sid = $q_sid|});
	
	return unless ($rv);
	
        if($delchild){
                # delete the children of this comment
                ($rv, $sth) = $S->db_select({
                        ARCHIVE => $S->_check_archivestatus($sid),
                        WHAT => 'sid, cid, pid',
                        FROM => 'comments',
                        WHERE => qq|sid = $q_sid AND pid = $q_cid|
                        });
                while (my $dc = $sth->fetchrow_hashref()){
                        $S->_delete_comment($dc->{sid}, $dc->{cid}, $dc->{pid},
1);
                        }
                }
        else {
                # Then reparent children of this comment
                $S->db_update({
                        ARCHIVE => $S->_check_archivestatus($sid),
                        WHAT => 'comments',
                        SET => qq|pid = $pid|,
                        WHERE => qq|sid = $q_sid AND pid = $q_cid|});
                }

	# Drop ratings for comment and recalculate mojo
	$S->_delete_ratings($sid, $cid, $uid);

	# Drop the commentcount cache value.
	$S->_count_cache_drop($sid);
	
	
	# Ok, now we've done it up right.
	return 1;
}

# Instead of completely deleting a comment, replace it with a 
# comment saying that the comment was deleted
sub _remove_comment {
	my $S = shift;
	my ($sid, $cid, $pid) = @_;
	
	$pid = 0 unless $pid;
	return unless $S->have_perm('comment_remove');

	$S->run_hook('comment_delete', $sid, $cid);

	my $removed_body = $S->{UI}->{BLOCKS}->{removed_comment_body};
	my $removed_subject = $S->{UI}->{BLOCKS}->{removed_comment_subject};
	$removed_body =~ s/%%nick%%/$S->{NICK}/g;
	$removed_subject =~ s/%%nick%%/$S->{NICK}/g;
	$removed_body = $S->dbh->quote($removed_body);
	$removed_subject = $S->dbh->quote($removed_subject);

	my $q_sid = $S->dbh->quote($sid);
	my $q_cid = $S->dbh->quote($cid);
	my $q_pid = $S->dbh->quote($pid);

	# Then "delete" the comment
	my ($rv, $sth) = $S->db_update({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'comments',
		SET => qq|comment = $removed_body, subject = $removed_subject|,
		WHERE => qq|cid = $q_cid AND sid = $q_sid|});
	
	return unless ($rv);
	# First, get the uid of comment poster
	($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'uid',
		FROM => 'comments',
		WHERE => qq|cid = $q_cid AND sid = $q_sid|});
	
	my $uid = $sth->fetchrow();
	
	# Drop ratings for comment and recalculate mojo
	$S->_delete_ratings($sid, $cid, $uid);
	
	# Ok, now we've done it up right.
	return 1;
}


sub get_comment_option {
	my $S = shift;
	my $option = shift;
	my $count = shift;
	return unless $option;
	
	# If we're trying to find the mode, we need to know how many comments
	# Can be overridden in the call, or just get all comments
	if ($option eq 'commentmode' && $count) {
		$S->_set_comment_mode($count);
	}
	
	# Check ratingchoice permission specially
	if ($option eq 'ratingchoice' && !$S->have_perm('comment_rate')) {
		return 'no';
	}
	# Check hidingchoice permission specially too
	if ($option eq 'hidingchoice' && ($S->{TRUSTLEV} != 2 && !$S->have_perm('super_mojo'))) {
		return 'no';
	}
	

	my $value;
	# try to find a value for the option by searching, in order, the params,
	# the session, the user prefs, and the site wide defaults
	if ($value = $S->cgi->param($option)) {
		# if the option was passed by param, make it the session default
		$S->session($option, $value);
		return $value;

	} elsif (
		($value = $S->session($option)) ||
		($value = $S->pref($option)) 
	) {
		# hack to make sure dynamic comment mode isn't accidently enabled when
		# it shouldn't be
		if (
			$option eq 'commentmode' &&
			!$S->{UI}->{VARS}->{allow_dynamic_comment_mode} && 
			($value eq 'dthreaded' || $value eq 'dminimal')
		) {
			$value = 'threaded';
		}

		return $value;
	}
}


#
# display_comments
#
# The main calling routine for collecting and formatting comments.
# Completely gutted and reworked by Hunter, 03/10/08. I've removed obsolete code for dealing with
# the "dynamic" op, and for the obsolete modes 'minimal', 'threaded', 'dminimal', and 'dthreaded':
# 'nested' and the flat modes handle pretty much all our cases these days. As a result, this code
# is much cleaner, but be warned that it can't be plugged into older scoop versions that _do_ use
# those modes.
#
#
sub display_comments {
	my $S = shift;
	my $sid  = shift;
	my $pid  = shift || 0;
	my $mode = shift;
	my $cid  = shift || $S->{CGI}->param('cid') || 0;
	
	# startup work... figure out how we're displaying things based on site and user preferences.
	
	my $story_id = ($S->{CGI}->param('id') || $S->get_story_id_from_sid($sid));
	my $dispmode = $S->get_comment_option('commentmode');
	my $type	 = $S->get_comment_option('commenttype');
	my $tool	 = $S->{CGI}->param('tool');
	my $qid		 = $S->{CGI}->param('qid');
	my $cgipid	 = $S->{CGI}->param('pid');
	my $op		 = $S->{CGI}->param('op');
	my $detail	 = $S->{CGI}->param('detail');
	my @cids	 = split /\D+/, $S->{CGI}->param('cids');
	
	my $is_shrink_mode = $S->_is_shrink_comments_mode();
	$detail ||= ($op eq 'update' or !$is_shrink_mode) ? 'f' : 's';
	
	# If the user is trying to look at a particular comment, fall back to mixed mode
	# to ensure we can actually see it.
	
	if ($type eq 'none') {
		return '' unless ($pid || $cid);
		$type = 'mixed';
	}
	
	# If comments disabled, just bail out.
	# This would only result from users viewing comments directly.
	
	return '<b>Comments have been Disabled for this Article</b>'
		if ($S->_check_commentstatus($sid) == -1);
	
	# This is for attaching polls. So the comments viewed with the poll are from the story that
	# the poll was attached to. This is so that we only change the sid if its an attached poll,
	# not if its just a normal poll.
	
	if ($S->_does_poll_exist($sid)) {
		my $s = $S->get_sid_from_qid($sid);
		$sid = $s if $s;
	}
	
	# Determine our collector and formatter arguments, based on our calling parameters. (See
	# create_comment_context() for more explanation: the context provides all necessary
	# information for the collector and formatter.) display_comments() is a catch-all routine
	# used all over the place, so we've got a lot of different things to test for.
	
	my $t_start = gettimeofday();
	
	my $order				= $S->get_comment_option('commentorder');
	my $rating				= $S->get_comment_option('commentrating');
	my $serial				= $S->check_serial($sid) || 0;
	my $section				= $S->_get_story_section($sid);
	
	my $alone_mode			= ($mode eq 'alone');
	my $collapsed_mode		= ($mode eq 'collapsed');
	my $preview_mode		= ($mode eq 'Preview');
	my $posting_comment		= ($op eq 'comments' && $tool eq 'post');
	
	my $display_new			= ($op ne 'update' || ($op eq 'update' && $detail ne 'c'));
	my $display_full		= (!$collapsed_mode and !$is_shrink_mode);
	my $display_actions		= (!$preview_mode and !$posting_comment);
	my $display_threaded	= ($dispmode ne 'flat_unthread');
	my $display_replies		= ($display_threaded and !$alone_mode);
	my $full_parent_paths	= ($display_threaded and $op eq 'comments');
	
	# If we're in 'collapsed' mode, pass a different block to the formatter.
	# Not sure why this doesn't use the "comment_collapsed" Scoop block.
	
	my $block = $collapsed_mode
		? $pid	? [ qq|%%norm_font%%%%new%% %%editorial%%<a href="javascript:void(toggle(%%cid%%))">%%subject%%</a> by %%name%%%%member%%, %%norm_font_end%%%%smallfont%%%%mini_date%% (<b>%%score%% / %%num_ratings%%</b>) [<a href="%%rootdir%%/comments/%%sid%%?pid=%%pid%%#%%cid%%">open</a>]%%smallfont_end%%| ]
				: [ qq|%%norm_font%%%%new%% %%editorial%%<a href="javascript:void(toggle(%%cid%%))">%%subject%%</a> by %%name%%%%member%%, %%norm_font_end%%%%smallfont%%%%mini_date%% (<b>%%score%% / %%num_ratings%%</b>) [<a href="%%rootdir%%/comments/%%sid%%/%%cid%%#%%cid%%">open</a>]%%smallfont_end%%| ]
		: undef;
	
	# create the context pseudoobject
	
	my $p = $S->create_comment_context({
		sid					=> $sid,
		story_id			=> $story_id,
		pid					=> $pid,
		cid					=> [ @cids, ($cid || ()) ],
		
# 		collected			=> undef,		# a placeholder for returning results
		type				=> $type,
		order				=> $order,
		rating				=> $rating,
		serial				=> $serial,
		section				=> $section,

		display_new			=> $display_new,
		display_full		=> $display_full,
		display_actions		=> $display_actions,
		display_threaded	=> $display_threaded,
		display_replies		=> $display_replies,
		full_parent_paths	=> $full_parent_paths,
		
		($block ? (block => $block) : ()),
	});
	
	# If we're able to cache the comment thread, attempt to do so.
	# We only attempt caching if it's a /story/ page with no modes or other magic going on.
	
	if (($op eq 'displaystory' or $op eq 'update') and !$tool and !$qid and !$p->{ pid } and !@{$p->{ cid }}) {
		$p->{ cache_as } = join ':', 'sthread', @{$p}{qw( story_id type order rating time_zone section story_mode story_is_archival )};
	}
	
	# TODO: Reset the display mode if the number of comments to be displayed is above certain
	# thresholds... but it has to iterate through, counting up the non-hidden-for-this-user
	# comments to do so. We should recalc the $p parameters to account for the new
	# dispmode, right?  That means making this a post-collector callback that completely reworks
	# $p... but we'll worry about that when and if we actually turn out to need it, in the future.

# 	my $comments_list = $p->{ collected };
# 	my $count = $S->_count_visible_comments($comments_list);
# 	warn "Count is $count\n" if ($DEBUG);
# 	$dispmode = $S->get_comment_option('commentmode', $count);
# 	warn "Set mode to $dispmode\n" if ($DEBUG);
	
	# Now call the formatter, which in turn pulls the requested comments
	# from the db or cache using the passed collector routine.

	my $comments = $S->format_comments($p);
###	my $comments = $S->run_box('hunter_comments',$carr,$p);
	
	# begin HTML formatting...
	
	my $comment_start = qq|
		<form id="rateAllForm" action="%%rootdir%%/" method="post">
		<div style="display:none;">
		<input type="hidden" name="op" value="$op" />
		<input type="hidden" name="sid" value="$sid" />
		<input type="hidden" name="pid" value="$pid" />
		<input type="hidden" id="detail" value="$detail" />
		<input type="hidden" id="serial" value="$serial" />
		</div>
		<ul class="cm i0">|;
	
	$comment_start .= 				 # if it's a poll, add a line about the qid
		  $S->_does_poll_exist($sid) ? qq| <INPUT TYPE="hidden" NAME="qid" VALUE="$sid"> |
		: $qid						 ? qq| <INPUT TYPE="hidden" NAME="qid" VALUE="$qid"> |
		: '';
	
	# add the inline editor
	
	my $uid = $S->{UID};
	my $user_anonymous = $uid < 0;		### or $S->{GID} eq 'Anonymous';
	my $user = $S->user_data($uid);
	
	my $may_post = (!$user_anonymous
					and ($op ne 'update')
					and $S->have_section_perm('norm_post_comments', $section)
					and $S->have_perm('comment_post'));
	
	my $sig = $user->{prefs}->{sig}
			? qq|<p class="sig">$user->{prefs}->{sig}</p>|
			: '';
	my $editor_preview = $may_post ? $S->{UI}->{BLOCKS}->{'editor_preview'} : '';
	   $editor_preview =~ s/%%sig%%/$sig/;
	my $inline_editor  = $may_post ? $S->{UI}->{BLOCKS}->{'inline_comment_editor'} : '';
	my $comments_end = qq|$editor_preview</ul>$inline_editor</form>|;
	
	if ($comments || $S->cgi->param('caller_op') ne 'storyonly') {
		$comments = $comment_start . $comments . $comments_end unless $detail eq 'c';
	}

	my $t_end = gettimeofday();
	my $t_total = sprintf("%.03f", $t_end-$t_start);
	my $size = int(length($comments) / 1024);
	if ($S->{UI}{VARS}{ debug_comment_thread_caching } and $S->have_perm('edit_user')) {
		$comments = "<blockquote>
			[$op:$tool:$qid:$detail:$pid:$cid]<br/>
			[CONTEXTER TIME: $p->{ t_context }]<br/>
			[PRE: $p->{ t_init_format }]<br/>
			[CACHE FETCH: $p->{ t_cache_fetch }] [$p->{ cache_vector }]<br/>
			[QUERY TIME: $p->{ t_collected }]<br/>
			[FORMATTER TIME: $p->{ t_formatted }]<br/>
			[CACHE STORE: $p->{ t_cache_store }] [$p->{ cache_vector }]<br/>
			[POST: $p->{ t_post_format }]<br/>
			[ALL: $t_total]<br/>
			[SIZE:${size}K]:</blockquote>" . $comments;
	}
	return $comments;
}


# ___________________________________________________________________________
# added these next routines -- Hunter
# ___________________________________________________________________________


# ___________________________________________________________________________
# 
# Is there a way to simplify all this damn parameter passing?  An object for all the parameters
# would do it, but with a speed penalty for all the method calling.  A speedier way would be to
# use a source filter. It's pretty safe in the scalar case; in the listref case it has issues.
#
# 	use Filter::Simple;
# 	FILTER_ONLY	code => sub { s/\sparam\s*\$(\w+)\s*\|\|=/my \$\1 = exists \$p->{ \1 } ? \$p->{ \1 } : \$p->{ \1 } =/g },
# 				code => sub { s/\sparam\s*\@\$(\w+)\s*\|\|=\s*([^;]+);/my \$\1 = exists \$p->{ \1 } ? \$p->{ \1 } : \$p->{ \1 } = \2; \$\1 = ref \$\1 ? \$\1 : [ \$\1 || () ]/g },
# 
# 	my $p = shift || { };		# a hash of display parameters
# 
# 	param  $k ||= $v;		# ideally should be //=; alters $p
# 	param @$k ||= $v;		# always a listref; alters $p; can't handle exprs with semicolons
# 
# 	use Data::Thunk qw(lazy);
# 	param  $k ||= lazy { $S->blah(); };		# lazy execution of closure
# 
# ___________________________________________________________________________


#
# create_comment_context
#
# The purpose of this routine is to provide a basic "context" object (merely a hash) capable of
# providing the voluminous parameter information necessary for collecting and formatting comments.
# Callers to collect_comments and format_comments are therefore free to specify only the
# parameters that are _not_ their default settings. By passing this context object around rather
# than having the various routines gather this info themselves, we only have to calculate these
# things once, regardless of how many routines we're calling.
#
# Yes, it's big. It's very big... the number of possible options, when displaying comments, is
# substantial. And it can't be done via subclasses because it's permission-based, meaning every
# user could have slightly different settings.
#
# The goal here is to provide all arguments such that the collector and formatter are (roughly)
# deterministic, within this context. This gives us all necessary information for creating cache
# vectors that are themselves deterministic. Note that some parameters are only useful for the
# collector, some for the formatter, and some for both. Since we are seldom expected to call a
# formatter without a collector, or vice versa, it isn't a problem to just do them all right off
# the bat.
#
# This is done as a hash simply for speed; a more rigorous definition would be object-based. Due
# to limitations of the language, it does mean that this routine is absurdly repetitive, though.
# Also, in an ideal world, any "expensive" but seldom-used defaults (like story_mode) would be
# lazy, perhaps using Data::Thunk or a similar module. We may do this later, if it proves useful.
#
#
sub create_comment_context {
	my $S = shift;
	my $p = shift;
	
	my $t_start = gettimeofday();

	my $sid = $p->{ sid };	# this is the only mandatory param; all others are derived or defaultable
	
	# might as well make sure these are in there too...
	
	$p->{ uid  } = $S->{UID}					unless exists $p->{ uid  };
	$p->{ user } = $S->user_data($p->{ uid })	unless exists $p->{ user };
	$p->{ user_anonymous } = ($p->{ uid } < 0)	unless exists $p->{ user_anonymous };	### or $S->{GID} eq 'Anonymous'?
	
	# Collector parameters; these determine which comments we should get, and from where.
	
	$p->{ type		} = $S->get_comment_option('commenttype')	unless exists $p->{ type		};	# ideally, we'd just set these three to hard defaults
	$p->{ order		} = $S->get_comment_option('commentorder')	unless exists $p->{ order		};	# since any caller would be well served to set them
	$p->{ rating	} = $S->get_comment_option('commentrating')	unless exists $p->{ rating		};	# themselves, via get_comment_option or otherwise.
	$p->{ time_zone			} = uc $S->pref('time_zone')		unless exists $p->{ time_zone	};
	$p->{ serial	 		} = $S->check_serial($sid) || 0		unless exists $p->{ serial		};
	$p->{ section			} = $S->_get_story_section($sid)	unless exists $p->{ section		};
	$p->{ story_mode		} = $S->_check_story_mode($sid)		unless exists $p->{ story_mode	};	# BUG: seldom used; should be lazy
	$p->{ story_is_archival	} = $S->_check_archivestatus($sid)	unless exists $p->{ story_is_archival };
	$p->{ last_story_cid	} = $S->fetch_highest_cid($sid)		unless exists $p->{ last_story_cid	};
	
	# The "display" parameters, defining how the comment thread should be formatted.
	
	$p->{ display_new		} = 1 unless exists $p->{ display_new		};	# display whether each comment is "new" for this user
	$p->{ display_replies	} = 1 unless exists $p->{ display_replies	};	# display the replies to each comment
	$p->{ display_raters	} = 1 unless exists $p->{ display_raters	};	# preload the lists of raters for each comment
	$p->{ display_actions	} = 1 unless exists $p->{ display_actions	};	# are we allowed to display "special" actions?
	$p->{ display_threaded	} = 1 unless exists $p->{ display_threaded	};	# vs. flat
	$p->{ display_full		} = 1 unless exists $p->{ display_full		};	# render comment body and actions (vs. not calculating them)
	$p->{ full_parent_paths } = 1 unless exists $p->{ full_parent_paths	};	# display full href to parent page, or just '#' ref?
	
	# The blocks to use for display.  These arrays define different blocks and delims for
	# different depths. Usually we specify only one or two depths: any depths reached that aren't
	# defined will use the delims of the last defined depth.  Note that these are not taken into
	# account when creating cache vectors, so if they can change independent of the passed display
	# parameters the cache won't update properly. We assume our caller only requests a cache if
	# they're explicitly passing us these only as invariant parameters.
	
	$p->{ block } = [ $p->{ display_full }
			? $S->{UI}{BLOCKS}{ comment_hunter }					# the normal comment block
			: $S->{UI}{BLOCKS}{ comment_hunter_collapsed } ]		# a smaller version
		unless exists $p->{ block };
	$p->{ block_ed } = [ $S->{UI}{BLOCKS}{ moderation_comment } ]	# the editorial comment block
		unless exists $p->{ block_ed };
	
	$p->{ delim_level_start	} = [ '', qq{\n<ul class="cm i1">}	] unless exists $p->{ delim_level_start	};
	$p->{ delim_level_end	} = [ '', qq{</ul>\n}				] unless exists $p->{ delim_level_end	};
	$p->{ delim_item_start  } = [ qq{\n<li id="c%%cid%%">}		] unless exists $p->{ delim_item_start	};
	$p->{ delim_item_end	} = [ qq{</li>}						] unless exists $p->{ delim_item_end	};
	
	# these parameters need to be coaxed into listrefs, if they aren't already in that form
	
	$p->{ cid				} = [ $p->{ cid				  } || () ] unless ref $p->{ cid				};
	$p->{ block				} = [ $p->{ block			  } || () ] unless ref $p->{ block				};
	$p->{ block_ed			} = [ $p->{ block_ed		  } || () ] unless ref $p->{ block_ed			};
	$p->{ delim_level_start	} = [ $p->{ delim_level_start } || () ] unless ref $p->{ delim_level_start	};
	$p->{ delim_level_end	} = [ $p->{ delim_level_end	  } || () ] unless ref $p->{ delim_level_end	};
	$p->{ delim_item_start	} = [ $p->{ delim_item_start  } || () ] unless ref $p->{ delim_item_start	};
	$p->{ delim_item_end	} = [ $p->{ delim_item_end	  } || () ] unless ref $p->{ delim_item_end		};
	
	my $t_end = gettimeofday();
	$p->{ t_context } = sprintf("%.03f", $t_end-$t_start);
	
	return $p;
}


#
# collect_comments
#
# The main collector for comments. The essential information required is the sid; the pid or
# cid(s) to start from; which "types" of comments should be displayed; whether to display "full"
# comment text or just summaries; threaded or flat display; whether to display replies.
# Note that there's a distinct difference between pid and cid: the first says to display all
# children of the parent comment, but not the parent comment itself, while the second displays
# _those particular comment(s)_ plus all their children.
#
# TODO: Caching.
#
# Output is a properly ordered "flattened tree" of comments -- a list of comments including
# "depth" information, children immediately following parents, that can be traversed as a tree.
#
#
sub collect_comments {
	my $S = shift;
	my $p = shift;

	my $t_start = gettimeofday();

	my $story_id= $p->{ story_id };
	my $sid		= $p->{ sid };
	my $pid		= $p->{ pid } || 0;
	my $cid		= $p->{ cid } || [];
	
	my $type	= $p->{ type	};
	my $order	= $p->{ order	};
	my $rating	= $p->{ rating	};
	
	my $time_zone			= $p->{ time_zone		  };
	my $section				= $p->{ section			  };
	my $story_mode			= $p->{ story_mode		  };	# seldom used; should be lazy
	my $story_is_archival	= $p->{ story_is_archival };
	
	my $display_replies 	= $p->{ display_replies	  };	# display the replies to each comment
	my $display_threaded	= $p->{ display_threaded  };	# vs. flat
	my $display_full		= $p->{ display_full	  };	# render comment body and actions (vs. not calculating them)
	
	# determine the desired ordering
	
	my $order_by = ($rating =~ /^unrate_/)
				? ($S->{CONFIG}->{mysql_version} =~ /^4/)
					? qq|norate asc, |
					: qq|norate desc, |
				: '';
	
	$order_by .= ($rating =~ /highest/)	? qq|points desc, |
				: ($rating eq 'lowest') ? qq|points asc, |
				: '';
	
	$order_by .= ($order eq 'oldest')
				? qq|date asc|
				: qq|date desc, cid desc|;
	
	# output format for dates (using session timezone info)
	
	my $date_format = $S->date_format('date');
	my $short_date  = $S->date_format('date', 'short');
	
	# the field that keeps track of whether a comment is still rateable
	
	my $rating_limit = ($S->{UI}->{VARS}->{limit_comment_rating_period})
		? "((UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(date)) / 3600) as hoursposted"
		: "NULL as hoursposted";
	
	# do we want the full comment, or will only parts of it do?
	
	my $select_comment = $display_full ? 'comment' : 'NULL as comment';
	my $select_sig	   = $display_full ? 'sig'     : 'NULL as sig';
	
	# start building the where clause...
	
	my $qstory_id = $S->dbh->quote($story_id);
	my $where = qq|story_id = $qstory_id|;
	   $where .= ( $pid						? qq| AND cid > $pid|
				: ($type eq 'topical')		? qq| AND pending = 0|
				: ($type eq 'editorial')	? qq| AND pending = 1|
				: ($type ne 'all' and !@$cid and $story_mode >= 0)  ? qq| AND pending = 0|
				: '');
	if (@$cid) {
		$pid = 0;
		if ($display_replies) {
			my $min_cid = $cid->[0];	# For multiples, treat each comment we're fetching as toplevel
			foreach (@$cid) { $min_cid = $_ if $min_cid > $_ }
			$where .= qq| AND cid >= $min_cid|;
		} elsif (@$cid == 1) {
			$where .= qq| AND cid = $cid->[0]|;
		} else {
			my $cids = join ',', @$cid;
			$where .= qq| AND cid IN ($cids)|;
		}
	}
	
	# (see the IX_COMMENT constants for the mandatory column indexes here)
	
	my($rv,$sth) = $S->db_select({
		ARCHIVE	 => $story_is_archival,
		WHAT	 => qq|sid, cid, pid, $date_format as f_date, $short_date as mini_date, $rating_limit, subject, $select_comment, uid, points, lastmod AS numrate, points IN (NULL) AS norate, pending, sig_status, $select_sig, commentip, recrate, trollrate, raters, id, story_id|,
 		FROM	 => 'comments',
		WHERE	 => $where,
 		ORDER_BY => $order_by,
	});
	my $comments = $sth->fetchall_arrayref();
	$sth->finish();
	
	# Set points and numrate to friendlier values if the comment hasn't yet been rated.
	# When grabbing a list of comments, treat them all as toplevel.
	
	foreach (@$comments) {
		$_->[ IX_COMMENT_points	 ] = 'none'	unless defined $_->[ IX_COMMENT_points ];
		$_->[ IX_COMMENT_numrate ] = '0'	if ($_->[ IX_COMMENT_numrate ] == '-1');
		$_->[ IX_COMMENT_pid	 ] =  0		if (@$cid > 1);
	}
	
	# Treeify the list, if necessary, by resorting and calculating depth information.
	# Otherwise just slice the needed elements out of it.
	
	$p->{ collected } = $comments = $display_threaded
		? $S->treeify_comments($comments,$pid,$cid)
		: $S->slice_comments($comments,$pid,$cid);
	
	# cache the result, if requested to do so
	
	;
	
	# preload user data for comment authors, since we know we'll at minimum need all their nicks
	
	my %known_users = map { $_->[ IX_COMMENT_uid ] => 1 } @$comments;
	$S->user_data([keys %known_users]);
	
	# and return the collected comments
	
	my $t_end = gettimeofday();
	$p->{ t_collected } = sprintf("%.03f", $t_end-$t_start);
	
	$p->{ collected } = $comments;
	return $comments;
}


#
# treeify_comments
#
# The basic routine to recurse down the comments tree, converting it to a tree and pulling out any
# results we're not interested in. Then we reflatten the tree into the proper order, returning
# order and depth info, but keeping the basic ordering we were first given. The advantage of this
# is that even though we have to recurse to get this info, we're doing it in very tight loops.
# That's much better than having to recurse in large functions with lots of initialization.
#
#
sub treeify_comments {
	my $S = shift;
	my $comments_list = shift;	# a sorted list of comments from which we can pull the needed subset
	my $pid = shift;			# where to start
	my $cid = shift;			# limit results to just one/some children?
	
	my %comments_hash = map { $_->[ IX_COMMENT_cid ] => $_ } @$comments_list;
	my $ids = [$pid || (), ref($cid) ? @$cid : ($cid || ())];
	   $ids = [ 0 ] unless @$ids;		# start from the top, if no ids given

	# Treeify, then flatten again in the proper order.  Handily, this throws away any comments
	# that aren't under the specific pid we're after, reducing our output list to only replies to
	# the parent comment.

	# Ideally, maybe we'd know which children were hidden from us, so we could throw them away
	# right now.  But note in a partial-compile scenario, different users could have different
	# levels of "hiding".
	
	my %child_tree;
	push @{$child_tree{ $_->[ IX_COMMENT_pid ] } ||= []}, $_->[ IX_COMMENT_cid ] foreach @$comments_list;
	my @ordered_cids = walk_treeified_comments(\%child_tree, @$ids);
	shift @ordered_cids if ($ordered_cids[0] == ($pid || 0));		# remove parent
	
	# Now calc the display depth of each comment. We do this after we've reordered them
	# to ensure we always calc parents before children.
	
	my %depth_tree;
	   $depth_tree{ $_ } = $depth_tree{ $comments_hash{$_}[ IX_COMMENT_pid ] }+1 foreach @ordered_cids;
	
	# finally, return the spliced and reordered comments list, including the new depth information.
	
	return [ map {
		$comments_hash{ $_ }[ IX_COMMENT_depth ] = $depth_tree{ $_ }-1;
		$comments_hash{ $_ };
	} @ordered_cids ];
}


#
# slice_comments
#
# Same concept as treeify_comments, but we want to be returned a flattened list
# in the original order, _not_ in children-immediately-after-parents nested order.
#
#
sub slice_comments {
	my $S = shift;
	my $comments_list = shift;	# a sorted list of comments from which we can pull the needed subset
	my $pid = shift;			# where to start
	my $cid = shift;			# limit results to just one/some children?
	
	my $ids = [$pid || (), ref($cid) ? @$cid : ($cid || ())];
	return $comments_list unless (@$ids);	# noop, if we're not actually limiting results
	
	my %comments_hash = map { $_->[ IX_COMMENT_cid ] => $_ } @$comments_list;

	my %child_tree;
	push @{$child_tree{ $_->[ IX_COMMENT_pid ] } ||= []}, $_->[ IX_COMMENT_cid ] foreach @$comments_list;
	my %used_cids = map { $_ => 1 } walk_treeified_comments(\%child_tree, @$ids);
	delete $used_cids{ $pid || 0 };		# remove parent
	
	# return the spliced comments list
	
	return[ grep { $used_cids{ $_->[ IX_COMMENT_cid ] } } @$comments_list ];
}


#
# a utility routine for treeify_comments()
#
sub walk_treeified_comments {
	my $child_tree = shift;
	map { ($_ || ()), &walk_treeified_comments( $child_tree, @{ $child_tree->{ $_ } || [] } ) } @_;
}


#
# _get_current_ratings
#
# Like _get_current_rating, but returns _all_ ratings for the given user
# in the given story.  It's more efficient to return them all at once.
#
#
sub _get_current_ratings {
	my $S = shift;
	my($sid, $uid) = @_;
	
	$S->_set_current_ratings($sid, $uid)
		unless defined($S->{ CURRENT_RATINGS }{$sid});
	
	return $S->{ CURRENT_RATINGS }{$sid};
}


#
# _is_shrink_comments_mode
#
# Whether or not to display "shrunken" comments instead of real ones.
# This is black magic.  From an understandability standpoint, it'd probably be better to have
# our callers just _tell_ us whether they want shrunken comments, rather than guess it based
# on our context. In truth, I'm not really sure 'shrink' mode is even still used anywhere.
#
#
sub _is_shrink_comments_mode {
	my $S = shift;
	my $op		= $S->{CGI}->param('op');
	my $detail	= $S->{CGI}->param('detail');
	
	my $dm = $S->{CGI}->param('commentDisplayMode')
		|| (($S->{UID} > 0) ? $S->pref('commentDisplayMode') : $S->session('commentDisplayMode'));

	($op eq 'update')
		? ($detail eq 's')
		: (($dm eq 'shrink')
			and not (  ($op eq 'comments')
					or ($op eq 'displaystory' && $detail eq 'f')
					or ($S->cgi->param('caller_op') eq 'story'
						&& ($S->pref('commentDisplayMode') eq 'hide' || $S->session('commentDisplayMode') eq 'hide'))
		  ));
}


sub is_comment_hidden {
	my $S = shift;
	my $comment = shift;		# hashref^arrayref of current comment

	my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
	return ( ($S->{UI}->{VARS}->{use_mojo})
			&& ($comment->[9] ne 'none')
			&& ($comment->[9] < $hide_thresh) );
}


sub _may_view_hidden_comments {
	my $S = shift;
	return 1 unless ($S->{UI}->{VARS}->{use_mojo});			# view all comments if mojo disabled
	
	# this convenience routine can return one of three values
	#	1	- view all hidden comments
	#	0	- never view hidden comments
	# undef - maybe: depends on the comment
	
	# If we just don't have permission, never view them
	if (($S->{TRUSTLEV} != 2) && (!$S->have_perm('super_mojo'))) {
		warn "(_may_view_hidden_comments: user permissions not sufficient. Skipping all.\n" if ($DEBUG);
		return 0;
	}
	# If we do have permission, see if we chose to never see them
	my $hide = $S->get_comment_option('hidingchoice');
	if ($hide eq 'no') {
		warn "(_may_view_hidden_comments: user chose to hide hidden comments. Skipping all.\n" if ($DEBUG);
		return 0;
	}
	# if we're choosing to "sometimes" see them, return undef
	return undef if ($hide eq 'untilrating');
	
	# otherwise we have permission and have chosen to see them; return true
	return 1;
}


sub _user_rated_this_comment {
	my $S = shift;
	my $comment = shift;					# hashref^arrayref of current comment
	
	# Ideally we would do these all batched as one database query, instead of iterating
	# through them, but it's unlikely we'll have more than a handful of hidden comments
	# per thread anyway.
	
	# Did I rate this comment?
	my $qsid = $S->dbh->quote($comment->[0]);
	my($rv, $sth) = $S->db_select({
		WHAT => 'uid',
		FROM => 'commentratings',
		WHERE => qq|uid = $S->{UID} AND cid = $comment->[1] and sid = $qsid|
	});
	my $rated = $sth->fetchrow();
	if ($rated) {
		warn "($comment->{pid}) User has rated this comment.\n" if ($DEBUG);
		return 1;
	}
	return 0;
}


sub _count_visible_comments {
	my $S = shift;
	my $comments = shift;

	my $may_view_hidden_comments = $S->_may_view_hidden_comments;
	my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
	my $use_mojo	= $S->{UI}->{VARS}->{use_mojo};
	
	return scalar @$comments if (!$use_mojo or $may_view_hidden_comments);
	
	scalar grep {
		   ($_->[ IX_COMMENT_points ] eq 'none')
		or ($_->[ IX_COMMENT_points ] >= $hide_thresh)
		or (not defined $may_view_hidden_comments and $S->_user_rated_this_comment($_))
	} @$comments;
}


# ___________________________________________________________________________
# end new routines -- Hunter
# ___________________________________________________________________________


sub skip_hidden_comment	{								# obsolete
	my $S = shift;
	my $comment = shift; # hashref^arrayref of current comment
	my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
	if (($S->{UI}->{VARS}->{use_mojo}) &&
	    ($comment->[9] ne 'none') && 
		($comment->[9] < $hide_thresh)) {
		
		# If we just don't have permission, skip it
		if (($S->{TRUSTLEV} != 2) && 
			(!$S->have_perm('super_mojo'))) {
			warn "($comment->[2]) Permissions not granted. Skipping.\n" if ($DEBUG);
			return 1;
		}
		# If we do have permission, see if we chose not to see
		my $hide = $S->get_comment_option('hidingchoice');
		if ($hide eq 'no') {
			warn "($comment->[2]) Chose to hide hidden comments. Skipping.\n" if ($DEBUG);
			return 1;
		} elsif ($hide eq 'untilrating') {
			# Did I rate this comment?
			my $qsid = $S->dbh->quote($comment->[0]);
			my ($rv, $sth) = $S->db_select({
				WHAT => 'uid',
				FROM => 'commentratings',
				WHERE => qq|uid = $S->{UID} AND cid = $comment->[1] and sid = $qsid|
			});
			my $rated = $sth->fetchrow();
			if ($rated) {
				warn "($comment->{pid}) Chose to hide hidden comments after rating, and has rated. Skipping.\n" if ($DEBUG);
				return 1;
			}
		}

	}
	return 0;
}

sub _count_current_comments {							# obsolete
	my $S = shift;
	my $pid = shift;
	my $count = shift || 0;
	   $count = 1 if ($pid && !$count);
	
	# If we're passed $params by our caller, use it. Otherwise seed it ourselves,
	# and pass it to our children to keep them from recalculating the same things.
	
	$S->{COMPARAM}->{may_view_hidden_comments} || $S->_may_view_hidden_comments;
	my $may_view_hidden_comments = $S->{COMPARAM}->{ may_view_hidden_comments };
	my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
	my $use_mojo	= $S->{UI}->{VARS}->{use_mojo};
	
	foreach my $i (@{$S->{CURRENT_COMMENT_THREAD}->{$pid}}) {
		my $comment = $S->{CURRENT_COMMENT_LIST}->[$i];
		my $cid = $comment->[1];
		
		warn "($pid) Looking at list item $i (cid: $cid, pid: $comment->[2])\n" if ($DEBUG);

		if ($comment->[2] != $pid) {
			warn "Wrong parent ($comment->[2]). Skipping.\n" if ($DEBUG);
			next;
		}
		
		# Skip the comment entirely if we're not supposed to see it.
		# we've pulled almost all of this work out of subroutines,
		# so that it's as efficient as possible
		my $comment_is_hidden = ($use_mojo && ($comment->[9] ne 'none') && ($comment->[9] < $hide_thresh));
		next unless (!$comment_is_hidden
						or $may_view_hidden_comments
						or (not defined $may_view_hidden_comments and !$S->_user_rated_this_comment($comment)));
		
		$count++;
		warn "Incremented counter to $count, exploring thread\n" if ($DEBUG);
		$count = $S->_count_current_comments($cid, $count);
	}
	
	return $count;
}

sub _get_comment_subject {								# obsolete
	my $S = shift;
	my $sid = shift;
	my $pid = shift;
	my $mode = shift;
	my $comment = shift;
	my $cid = $comment->[1];
	
	# If we're passed $params by our caller, use it. Otherwise seed it ourselves,
	# and pass it to our children to keep them from recalculating the same things.
	
	$S->{COMPARAM}->{check_archivestatus} = $S->_check_archivestatus($sid);
	$S->{COMPARAM}->{story_highest_index} = $S->story_highest_index($sid);
	my $check_archivestatus = $S->{COMPARAM}->{ check_archivestatus };
	my $story_highest_index = $S->{COMPARAM}->{ story_highest_index };
	
	my $user = $S->user_data($comment->[8]);
	my $postername = $user->{nickname};
	
	my $ed_tag = '';
	   $ed_tag = 'Editorial: ' if ($comment->[12]);
	
	my $new = '';
	# Check for highest index
	if ($S->{UI}->{VARS}->{show_new_comments} eq 'all') {
		#if ($S->{UI}->{VARS}->{use_static_pages} && $S->{GID} eq 'Anonymous') {
			#$new = '%%new_'.$cid.'%%';
			#warn "New is $new\n";
		#} elsif (($S->{UID} >= 0) && !$check_archivestatus) {
		
		$new = $S->{UI}->{BLOCKS}->{new_comment_marker}
			if (($S->{UID} >= 0) && !$check_archivestatus && ($cid > $story_highest_index));
	}

	my $openurl = "%%rootdir%%/comments/$sid";
	   $openurl .= $pid
			? "?pid=$pid#$cid"
			: "/$cid#$cid";
	
	# Make the subject an expand link for dynamic mode, or an open link otherwise.

	my($link,$open_link);
	if ($mode eq 'dminimal' || $mode eq 'dthreaded' || $mode eq 'collapsed') {
		$link		 = qq|javascript:void(toggle($cid))|;
		$open_link	 = qq| [<a href="$openurl">open</a>]|;
	} else {
		$link		 = $openurl;
		$open_link	 = '';
	}

	my $member = $S->{UI}->{BLOCKS}->{"mark_$user->{perm_group}"};

	# This should probably be made into a block
	return qq|%%norm_font%%$new $ed_tag<a href="$link">$comment->[6]</a> by $postername$member, %%norm_font_end%%%%smallfont%%$comment->[4] (<b>$comment->[9] / $comment->[10]</b>)$open_link%%smallfont_end%%|;

}

sub _get_comment_list_delimiters {								# obsolete
	my $S = shift;
	my $sid = shift;
	my $dispmode = shift;
	my $depth = shift || 0;
	my $plus  = $S->{UI}->{BLOCKS}->{dynamic_expand_link}   || '+';
	my $minus = $S->{UI}->{BLOCKS}->{dynamic_collapse_link} || '-';
	my $pid = $S->{CGI}->param('pid');
	my $cid = $S->{CGI}->param('cid');

	my($start, $end, $level_start, $level_end, $item_start, $item_end);
	
	# I've reordered these to do the easiest compares first -- Hunter
	
	if ($dispmode eq 'nested') {
		$start = '<ul class="cm i1">';	#'<DL>';
		$end = '</ul>';					#'</DL>';
		$level_start = '';				#'<DT></DT><DD>';
		$level_end = '';				#'</DD>';
		return($start, $end, $level_start, $level_end, $item_start, $item_end);
	} 
	
	if ($dispmode eq 'dthreaded' || $dispmode eq 'dminimal') {
		# We don't want to indent the first level
		if ($depth <= 0) {
			$start = '';
			$end   = '';
		} else {
			$start = '<DIV STYLE="margin-left: 2.5em">';
			$end   = '</DIV>';
		}
		# If we're at the top level of a dthreaded thread, make a
		# collapse link. Otherwise, make an expand link.
		my($class,$text);
		if ($depth <= 0 && ($dispmode eq 'dthreaded' || $pid || $cid)) {
			$class = 'dynexpanded';
			$text  = $minus;
		} else {
			$class = 'dyncollapsed';
			$text  = $plus;
		}
		$item_start = qq|<TABLE><TR>
			<TD VALIGN="top">%%norm_font%%<TT><A ID="toggle!cid!" STYLE="text-decoration:none" HREF="javascript:void(toggle(!cid!))">$text</A></TT>&nbsp;%%norm_font_end%%</TD>
			<TD><DIV CLASS="$class" ID="content!cid!">|;
		$item_end = qq|</DIV></TD></TR></TABLE>|;
		return($start, $end, $level_start, $level_end, $item_start, $item_end);
	}

	if ($dispmode ne 'flat' && $dispmode ne 'flat_unthread') {
		$start		 = '<UL>';
		$end		 = '</UL>';
		$level_start = '<UL>';
		$level_end	 = '</UL>';
		$item_start  = '<LI>';
		$item_end	 = '</LI>';
	}
		
	return($start, $end, $level_start, $level_end, $item_start, $item_end);
}	

sub get_list {											# obsolete
	my $S = shift;
	my $sid = shift;
	my $pid = shift;
	my $dispmode = shift || $S->get_comment_option('commentmode');
	my $depth = shift || 1;
	
	# If we're passed $params by our caller, use it. Otherwise seed it ourselves,
	# and pass it to our children to keep them from recalculating the same things.
	# In the cache, we'll put anything that's difficult to calculate, is frequently
	# used, and that doesn't ever change within a particular request and story.
	
	$S->{COMPARAM} ||= {
		check_archivestatus		 => $S->_check_archivestatus($sid),
		story_highest_index		 => $S->story_highest_index($sid),
		may_view_hidden_comments => $S->_may_view_hidden_comments,
		dispmode				 => $S->get_comment_option('commentmode'),
	};
	$dispmode ||= $S->{COMPARAM}->{ dispmode };
	my $may_view_hidden_comments = $S->{COMPARAM}->{ may_view_hidden_comments };
	my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
	my $use_mojo	= $S->{UI}->{VARS}->{use_mojo};
	
	# No thread list if unthreaded flat. just return.
	return if ($dispmode eq 'flat_unthread');
	
	my $cid = $S->{CGI}->param('cid');
	my $plus = $S->{UI}->{BLOCKS}->{dynamic_expand_link}  || '+';
	my $wait = $S->{UI}->{BLOCKS}->{dynamic_loading_link} || 'x';
	my @cids;
	
	my $list;
	
	if (!$S->{UI}->{VARS}->{allow_dynamic_comment_mode}) {
		if ($dispmode eq 'dthreaded') {
			$dispmode = 'threaded';
		} elsif ($dispmode eq 'dminimal') {
			$dispmode = 'minimal';
		}
	}
	
	# Only build the delimiter list for this mode and level if nothing else has already built it.
	# otherwise, we'll be redoing this all over again for every subthread, which is
	# pretty inefficient.
	
	my($start, $end, $level_start, $level_end, $item_start, $item_end) =
		@{ $S->{COMPARAM}->{ delimiters }{ $dispmode }[ $depth ]
			||= [ $S->_get_comment_list_delimiters($sid, $dispmode, $depth) ] };
	
	# loop through the comments and comment subthreads
	
	foreach my $i (@{$S->{CURRENT_COMMENT_THREAD}->{$pid}}) {
		my $comment = $S->{CURRENT_COMMENT_LIST}->[$i];
		my $cid = $comment->[1];
		
		warn "($pid) Looking at list item $i (cid: $cid, pid: $comment->[2])\n" if ($DEBUG);
		# Skip this if it's not the right level
		#if ($comment->{pid} != $pid) {
		#	warn "($pid) Wanted pid $pid. Skipping\n" if ($DEBUG);
		#	$i++;
		#	next;
		#} 
		
		# Skip the comment entirely if we're not supposed to see it.
		# we've pulled almost all of this work out of subroutines,
		# so that it's as efficient as possible
		my $comment_is_hidden = ($use_mojo && ($comment->[9] ne 'none') && ($comment->[9] < $hide_thresh));
		next unless (!$comment_is_hidden
						or $may_view_hidden_comments
						or (not defined $may_view_hidden_comments and !$S->_user_rated_this_comment($comment)));
		
		# Otherwise, splice off this comment and get busy
		
		warn "($pid) We want this one! Formatting.\n" if ($DEBUG);
		push @cids, $cid;

		# Set $i back to 0, because we don't know how many comments
		# we'll be pulling off the list after this...
		#$i = 0;
		
		$comment->[9]  = 'none'	unless defined($comment->[9]);
		$comment->[10] = '0'	if ($comment->[10] == '-1');

		if ($dispmode eq 'nested' || $dispmode eq 'flat' || $dispmode eq 'flat_unthread') {
			$list .=  $level_start
					. $S->format_comment($comment)
					. $level_end;
		} else {
			my $item_start_subst = $item_start;
			   $item_start_subst =~ s/!cid!/$cid/g;
			$list .=  $item_start_subst
					. $S->_get_comment_subject($sid, $pid, $dispmode, $comment)
					. $item_end;
			
		 	my($sublist,@subcids) = $S->get_list($sid, $cid, $dispmode, $depth+1);
			$list .= $sublist;
			push @cids, (@subcids);
		}
	}
	
	$list = $start . $list . $end if ($list);

	if (@cids && ($dispmode eq 'dminimal' || $dispmode eq 'dthreaded')) {
		# Add a bit of script to save the replies list
		my $cids = join ',', @cids;
		   $cids .= ',null' if (scalar(@cids) == 1);
		$list .= qq|
<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript"><!--
replies[$pid] = new Array($cids);
//--></SCRIPT>|;
	}
	return ($list,@cids);
}

sub anon_comment_warn {
	my $S = shift;
	my $subject = shift;
	if (!$S->have_perm( 'comment_post' )) {
		my $time = localtime;
		warn "<< WARNING >> Anonymous comment disallowed at $time. IP: $S->{REMOTE_IP}, Subject: $subject\n";
		return 0;
	}
	return 1;
}

sub fetch_highest_cid {
	my $S = shift;
	my $sid = shift;
	
	my $quoted_sid = $S->dbh->quote($sid);
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'cid',
		FROM => 'comments',
		WHERE => qq|sid = $quoted_sid|,
		ORDER_BY => 'cid DESC',
		LIMIT => 1
	});
	my $highest = $sth->fetchrow();
	$sth->finish();
	return $highest;
}


sub _comment_breakdown {
	my $S = shift;
	my $sid = shift;
	my ($topical, $editorial, $pending, $highest);
	
	my $resource = $sid.'_comments';
	my $element = $sid.'_commentcounts';
	
	if (my $cached = $S->cache->fetch_data({resource => $resource, 
	                                        element => $element})) {
		$topical   = $cached->{topical};
		$editorial = $cached->{editorial};
		$pending   = $cached->{pending};
		$highest   = $cached->{highest};
		
		return ($topical, $editorial, $pending, $highest);
	}
	
	my $cache_me;
	my $quoted_sid = $S->dbh->quote($sid);
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'pending, count(*)',
		FROM => 'comments',
		WHERE => qq|sid = $quoted_sid|,
		GROUP_BY => 'pending'
	});
	
	while (my $row = $sth->fetchrow_arrayref()) {
		($row->[0] == 0) ? $topical = $row->[1] : $editorial = $row->[1];
	}
	$sth->finish();
	$cache_me->{topical} = $topical || 0;
	$cache_me->{editorial} = $editorial || 0;
	
	if ($S->{UI}->{VARS}->{use_mojo}) {
		my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
		my ($rv, $sth) = $S->db_select({
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT => 'COUNT(*)',
			FROM => 'comments',
			WHERE => qq|sid = $quoted_sid AND points < $hide_thresh|
		});
		
		$pending = $sth->fetchrow() || 0;
		$sth->finish();
		$cache_me->{pending} = $pending;	
	}

	$highest = $S->fetch_highest_cid($sid);
	$cache_me->{highest} = $highest;
	
	$S->cache->cache_data({resource => $resource,
	                       element => $element,
	                       data => $cache_me});

	return ($topical, $editorial, $pending, $highest);
}

sub _commentcount {
	my $S = shift;
	my $sid = shift;
                
	my $count = 0;  
                
	my($a,$b,$c,$d) = $S->_comment_breakdown($sid);
	$count = $a + $b;
        
	return $count;
}

sub _comment_highest {
	my $S = shift;
	my $sid = shift;
	
	my ($a,$b,$c,$d) = $S->_comment_breakdown($sid);
	return $d;
}

sub _count_cache_drop {
	my $S = shift;
	my $sid = shift;
	my $resource = $sid.'_comments';
	my $element = $sid.'_commentcounts';
	
	# Drop our memory cache for this story
	$S->cache->clear({resource => $resource, element => $element});
	$S->cache->stamp_cache($resource, time(), 1);
	$S->_commentcount($sid);
	
	return;
}	

1;	
