=head1 AdminStories.pm

This is just a bit of documentation I've added in here while fixing a bug
that GandalfGreyhame first discovered in the wild
-Andrew

=head1 Functions

=cut


package Scoop;
use strict;
my $DEBUG = 0;

=pod

=over 4

=item *
edit_story()

This is what generates the Admin Edit Story form.  It takes no arguments, other than what
it gets from the form, through $S->{CGI}->param(). If the user wants to save the story, or 
update it, $S->save_story() is called. Otherwise the form is set up for more editing.

=back

=cut

sub edit_story {
	my $S = shift;
	warn "(edit_story) Starting..." if $DEBUG;
	# don't check for spellcheck perm here because fiddiling with params won't
	# do any damage
	if ($S->{CGI}->param('spellcheck')) {
		$S->param->{save} = undef;
		$S->param->{preview} = 'Preview';
	}

	my $sid = $S->{CGI}->param('sid');
	my $preview = $S->{CGI}->param('preview');
	my $save = $S->{CGI}->param('save');
	my $delete = $S->{CGI}->param('delete');
	my $delconf = $S->{CGI}->param('delconf');
	my $archive = $S->{CGI}->param('archive');
	my $params = $S->{CGI}->Vars_cloned;

	# See if we're trying to edit a story that's had a new sid made
	# after publication. If we are, redirect to the new sid
	if(!$S->_check_for_story($sid)){
		my $nsid = $S->check_for_dsid($sid);
		if ($nsid){
			my $redir = $S->{UI}->{VARS}->{site_url} . "/admin/story/$nsid";
			$S->{APACHE}->headers_out->{'Location'} = $redir;
			$S->{HEADERS_ONLY}=1;
			}
		}

	# Check for extended perms here -- if users are allowed to edit their own entries,
	# they will only have "edit_my_stories", not "story_admin"
	return "foo $sid" unless ($S->check_edit_story_perms($sid));

	if ($S->{CGI}->param('spellcheck') && $S->spellcheck_enabled()) {
		foreach my $e (qw(introtext bodytext)) {
			$params->{$e} = $S->spellcheck_html($params->{$e});
		}

		foreach my $e (qw(title dept)) {
			$params->{$e} = $S->spellcheck_string($params->{$e});
		}
	}

	my $content;
	my $keys = {};
	
	if ($archive) {

		if ($S->archive_story($sid)) {
			$content = $S->{UI}->{BLOCKS}->{edit_story_archive_success};
			return $content;
		} else {
			$content = $S->{UI}->{BLOCKS}->{edit_story_archive_fail};
			return $content;
		}

	} elsif ($delete) {
		if(!$delconf){
                    $content .= qq|<tr><td>%%norm_font%%Sorry, story $sid deletion not confirmed.</td></tr></table>|;
		    return $content;
		    }
		$content = $S->delete_story($sid);
		return $content;
	}

	my $tmpsid;
	my $error;
	my $save_error;		# this is used later, when we call edit_story_form,
						# to let it know that the save failed, thus redisplay the data
						# not used right now, will be used later

	# Check the formkey, to prevent duplicate postings
	if ($save && !$S->check_formkey()){
		$error = "Invalid form key. This is probably because you clicked 'Post' or 'Preview' more than once. DO HIT 'BACK'! Make sure you haven't already posted this once, then go ahead and post or preview from this screen.";
		$preview = 'Preview';
	}

	if ($save) {
		warn "Saving $sid..." if $DEBUG;
		($sid, $error) = $S->save_story();
		if ($sid) {
			$preview = 'Saved';
		} else {
			$preview = 'Preview';
			$save_error = 'Save Error';
		}

		# if we are using editorial auto-voting, clear votes on story update
		# to re-mark as "new"
		$S->_clear_auto_votes($sid);
	}

	if ($preview) {
		warn "Previewing $sid..." if $DEBUG;
		$tmpsid = 'preview';
		
		if ($preview eq 'Publish') {
			warn "This is an update" if $DEBUG;
			($sid, $error) = $S->save_story();
			$tmpsid = $sid;
			$S->_clear_auto_votes($sid);
		}
		else {
			($sid, $error) = $S->save_story();
			# slightly weird, but we have to adjust the intro
			# and body text to preview right.
			$params->{introtext} = $S->filter_comment($params->{introtext}, 'intro', $params->{posttype});  
                	$params->{bodytext} = $S->filter_comment($params->{bodytext}, 'body', $params->{posttype});
                	$params->{title} = $S->filter_subject($params->{title});
			}

		# Give a helpful message
		$keys->{error} = $error;
		warn "Preview: Getting $tmpsid for display" if $DEBUG;
		$keys->{story} = $S->old_displaystory($tmpsid, $params);
	
	} 


	# This if and the above if will never both happen, since $tmpsid is set
	# right away in the above one.
	if ($sid && !$tmpsid) {

		$keys->{error} = $error;

		warn "SID: Getting $sid for display" if $DEBUG;
		$keys->{story} = $S->displaystory($sid);
	}
	
	if ($preview ne 'Saved') {
		$keys->{edit_form} = $S->edit_story_form();
	}
	
	$content = $S->interpolate($S->{UI}->{BLOCKS}->{edit_story_admin_page}, $keys);	
	return $content;
}

sub check_edit_story_perms {
	my $S = shift;
	my $sid = shift;

	# story_admin is the universal story edit perm
	return 1 if ($S->have_perm('story_admin'));
	
	# if not, we have to be editing an existing story
	return 0 unless ($sid);

	my $r = $S->story_data_arr([$sid]);
	my $story = $r->[0];
	warn "AID: $story->[2]\n" if $DEBUG;
	return 1 if ($S->have_perm('edit_my_stories') && $story->[2] == $S->{UID});
	return 0;
}


sub _clear_auto_votes {
	my $S = shift;
	my $sid = shift;

	return unless $S->{UI}->{VARS}->{story_auto_vote_zero} && $sid;

	my ($rv, $sth) = $S->db_delete({
		FROM  => 'storymoderate',
		WHERE => "sid = '$sid'"
	});
	$sth->finish;

	$S->save_vote($sid, '0', 'N');
}

=pod

=over 4

=item * delete_story

This routine will delete the story $sid

=cut

sub delete_story {
	my $S = shift;
	my $sid = $S->{CGI}->param('sid');
 	my $quote_sid = $S->{DBH}->quote($sid);
	my $user_delete_hide = $S->{UI}->{VARS}->{user_delete_hide};
	
	# If not admin, just hide the story
	if (!$S->have_perm('story_admin') && $user_delete_hide) {
		my ($rv, $sth) = $S->db_update({
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT => 'stories',
			SET => 'displaystatus = -1',
			WHERE => qq{sid = $quote_sid}
		});
		$sth->finish();
		$S->run_hook('story_hide', $sid);
	 	my $return = $S->{UI}->{BLOCKS}->{story_hide_message};
		$return =~ s/%%sid%%/$sid/g;
		return $return;
	}	

	my $archived = $S->_check_archivestatus($sid);
 	my @clean_up_args = ("comments", "ratings", "votes");
	push(@clean_up_args, 'viewed_stories') unless $archived;
 
 	my $attached_poll_qid = $S->get_qid_from_sid($sid);
 	if( $attached_poll_qid ) {
 		push(@clean_up_args, "poll");
 	}
 	
	$S->run_hook('story_delete', $sid);
	
	
 	$S->_clean_up_db($sid, @clean_up_args);

 	my ($rv, $sth) = $S->db_delete({
 		DEBUG => 0,
		ARCHIVE => $archived,
 		FROM => 'stories',
 		WHERE => qq|sid = $quote_sid|});

	for (my $i = 1; $i < 5; $i++){
		$S->cache->remove("main-${i}_15");
		$S->cache->remove("section-${i}_15");
		}
 		
 	
 	my $return = $S->{UI}->{BLOCKS}->{story_delete_message};
	$return =~ s/%%sid%%/$sid/g;

 	return $return;
}

sub archive_stories {
	my $S = shift;
	my $story_age = $S->{UI}->{VARS}->{story_archive_age};
	my $comment_age = $S->{UI}->{VARS}->{comment_archive_age};

	return "story_age not set" unless ($story_age >0);

	return "No archive setup" unless ($S->{HAVE_ARCHIVE});

	my ($rv, $sth) = $S->db_select({
		DEBUG => 0,
		WHAT => 'sid',
		FROM => 'stories',
		WHERE => $S->db_date_add(time, "$story_age day") . "< now()"
	});

	my (@sids, $rv2, $sth2, $qsid, $sid);
	while ($sid = $sth->fetchrow()) {
		if ($comment_age > 0) {
			$qsid = $S->{DBH}->quote($sid);
			($rv2, $sth2) = $S->db_select({
				DEBUG => 0,
				FROM => 'comments',
				WHAT => 'sid',
				WHERE => $S->db_date_add('date', '$comment_age day') . ' >= now() AND sid = $qsid',
				LIMIT => 1
			});
			if ($sth2->fetchrow() ne $sid) {
				push(@sids, $sid);
			}
			$sth2->finish();
		} else {
			push(@sids, $sid);
		}
	}
	$sth->finish();

	# now go through the list, and archive those sids.
	# Check they are not attatched to valid adverts first.
	
	my ($ad, $canarchive);
	foreach $sid (@sids) {
		$qsid = $S->{DBH}->quote($sid);
		($rv, $sth) = $S->db_select({
			DEBUG => 0,
			FROM => 'ad_info',
			WHAT => 'views_left, perpetual',
			WHERE => 'active = 1 AND ad_sid = '.$qsid});
		$canarchive = 1;
		if ($rv ne '0E0') {
			$ad = $sth->fetchrow_hashref();
			if (($ad->{views_left} > 0) || ($ad->{perpetual} = 1)) {
				#warn "Can't Archive story : $sid : active advert";
				$canarchive = 0;
			}
		}
		if ($canarchive) {	
			#warn "Archive story : $sid";
			$S->archive_story($sid);
		}
		$sth->finish();
	}
	return 1;

}

sub archive_story {
	my $S = shift;
	my $sid = shift;
	my $result = 0;

	#warn "Archive_story: $sid";

	return 0 if ($S->_check_archivestatus($sid));
	return 0 unless ($S->{DBHARCHIVE});

 	#my $attached_poll_qid = $S->get_qid_from_sid($sid);
	
 	#if( $attached_poll_qid ) {
 		#archive poll
	#}

 	my $quote_sid = $S->{DBH}->quote($sid);

	my ($rv, $sth) = $S->db_select({
		DEBUG => 0,
		WHAT => '*',
		FROM => 'stories',
		WHERE => qq|sid = $quote_sid|});
	my $story = $sth->fetchrow_hashref();
	$sth->finish();

	# if using macros, then render the macro(s) before archiving.
	# Render both introtext and bodytext.

	my $introtext = $story->{introtext};
	my $bodytext = $story->{bodytext};

	if (exists($S->{UI}->{VARS}->{use_macros}) && $S->{UI}->{VARS}->{use_macros}) {
		$introtext = $S->process_macros($introtext,'intro');
		$bodytext = $S->process_macros($bodytext,'body');
	}

	my @tosave = ($S->{DBHARCHIVE}->quote($story->{sid}),
		      $S->{DBHARCHIVE}->quote($story->{tid}),
		      $S->{DBHARCHIVE}->quote($story->{aid}),
		      $S->{DBHARCHIVE}->quote($story->{title}),
		      $S->{DBHARCHIVE}->quote($story->{dept}),
		      $S->{DBHARCHIVE}->quote($story->{time}),
		      $S->{DBHARCHIVE}->quote($introtext),
		      $S->{DBHARCHIVE}->quote($bodytext),
		      $story->{writestatus},
		      $story->{hits},
		      $S->{DBHARCHIVE}->quote($story->{section}),
		      $story->{displaystatus},
		      $story->{commentstatus},
		      $story->{totalvotes},
		      $story->{score},
		      $story->{rating},
		      $S->{DBHARCHIVE}->quote($story->{attached_poll}),
		      $story->{sent_email},
		      $story->{edit_category});

	my ($rvarch, $stharch) = $S->db_insert({
		DEBUG => 0,
		ARCHIVE => 1,
		INTO => 'stories',
		COLS => 'sid, tid, aid, title, dept, time, introtext, bodytext, writestatus, hits, section, displaystatus, commentstatus, totalvotes, score, rating, attached_poll, sent_email, edit_category',
		VALUES => "$tosave[0],$tosave[1],$tosave[2],$tosave[3],$tosave[4],$tosave[5],$tosave[6],$tosave[7],$tosave[8],$tosave[9],$tosave[10],$tosave[11],$tosave[12],$tosave[13],$tosave[14],$tosave[15],$tosave[16],$tosave[17],$tosave[18]"
	});
	$stharch->finish();

	if ($rvarch) {
		($rv, $sth) = $S->db_delete({
			DEBUG => 0,
			FROM => 'stories',
			WHERE => qq|sid = $quote_sid|});
	}
	$story = '';

	($rv, $sth) = $S->db_select({
		DEBUG => 0,
		WHAT => '*',
		FROM => 'comments',
		WHERE => qq|sid = $quote_sid|});
	my $comments;
	my @archived = ();
	while ($comments = $sth->fetchrow_hashref()) {

		# if using macros, then render the macro(s) before archiving comments.

		my $comment = $comments->{comment};

		if (exists($S->{UI}->{VARS}->{use_macros}) && $S->{UI}->{VARS}->{use_macros}) {
			$comment = $S->process_macros($comment,'comment');
			$comments->{sig} = $S->process_macros($comments->{sig},'pref');
		}

		@tosave = ($S->{DBHARCHIVE}->quote($comments->{sid}),
			   $comments->{cid},
			   $comments->{pid},
			   $S->{DBHARCHIVE}->quote($comments->{date}),
			   $comments->{rank} || "NULL",
			   $S->{DBHARCHIVE}->quote($comments->{subject}),
		 	   $S->{DBHARCHIVE}->quote($comment),
			   $comments->{pending} || "0",
			   $comments->{uid},
			   $comments->{points} || "NULL",
			   $comments->{lastmod} || "NULL",
			   $comments->{sig_status} || "NULL",
		  	   $S->{DBHARCHIVE}->quote($comments->{sig}) || "NULL",
			   $S->{DBHARCHIVE}->quote($comments->{commentip}) || "NULL");
		($rvarch, $stharch) = $S->db_insert({
			DEBUG => 0,
			ARCHIVE => 1,
			INTO => 'comments',
			COLS => 'sid, cid, pid, date, rank, subject, comment, pending, uid, points, lastmod, sig_status, sig, commentip',
			VALUES => "$tosave[0],$tosave[1],$tosave[2],$tosave[3],$tosave[4],$tosave[5],$tosave[6],$tosave[7],$tosave[8],$tosave[9],$tosave[10],$tosave[11],$tosave[12],$tosave[13]"});
		$stharch->finish();
		if ($rvarch) {
			push(@archived,($tosave[1]));
		}
	}
	$comments = '';
	$sth->finish();

	foreach my $todelete (@archived) {
		($rv, $sth) = $S->db_delete({
			DEBUG => 0,
			FROM => 'comments',
			WHERE => qq|sid = $quote_sid AND cid = $todelete|});
		$sth->finish()
	}
	
	$rvarch = 1;
	if ($S->{UI}->{VARS}->{archive_moderations}) {
		($rv, $sth) = $S->db_select({
			DEBUG => 0,
			WHAT => '*',
			FROM => 'storymoderate',
			WHERE => qq|sid = $quote_sid|});
		$rvarch = $rv;
		my $moderation;
		while ($moderation = $sth->fetchrow_hashref()) {
			@tosave = ( $S->{DBHARCHIVE}->quote($moderation->{sid}),
				  $moderation->{uid},
				  $S->{DBHARCHIVE}->quote($moderation->{time}),
				  $moderation->{vote},
				  $S->{DBHARCHIVE}->quote($moderation->{section_only}));
			($rvarch, $stharch) = $S->db_insert({
				DEBUG => 0,
				ARCHIVE => 1,
				INTO => 'storymoderate',
				COLS => 'sid, uid, time, vote, section_only',
				VALUES => "$tosave[0],$tosave[1],$tosave[2],$tosave[3],$tosave[5]"});
			$stharch->finish();
		}
		$sth->finish();
	}
	if ($rvarch) {
		($rv, $sth) = $S->db_delete({
			DEBUG => 0,
			FROM => 'storymoderate',
			WHERE => qq|sid = $quote_sid|});
		$sth->finish();
	}

	$rvarch = 1;
	if ($S->{UI}->{VARS}->{archive_ratings}) {
		($rv, $sth) = $S->db_select({
			DEBUG => 0,
			WHAT => '*',
			FROM => 'commentratings',
			WHERE => qq|sid = $quote_sid|});
		my $ratings;
		$rvarch = $rv;
		while ($ratings = $sth->fetchrow_hashref()) {
			@tosave = ( $ratings->{uid},
				    $ratings->{rating},
				    $ratings->{cid},
				    $S->{DBHARCHIVE}->quote($ratings->{sid}),
				    $S->{DBHARCHIVE}->quote($ratings->{rating_time}));
			($rvarch, $stharch) = $S->db_insert({
				DEBUG => 0,
				ARCHIVE => 1,
				INTO => 'commentratings',
				VALUES => "$tosave[0],$tosave[1],$tosave[2],$tosave[3],$tosave[4]"});
			$stharch->finish();
		}
		$sth->finish();
	}
	if ($rvarch) {
		($rv, $sth) = $S->db_delete({
			DEBUG => 0,
			FROM => 'commentratings',
			WHERE => qq|sid = $quote_sid|});
		$sth->finish();
	}

	($rv, $sth) = $S->db_delete({
			DEBUG => 0,
			FROM => 'viewed_stories',
			WHERE => qq|sid = $quote_sid AND hotlisted = 0|});
	$sth->finish();

	return 1;

}

=item *
save_story($mode)

This is the main routine for saving stories.  When you click save, or update, this is called.
$mode is by default 'full', but it can also be anything else you like, since there are only 
2 behaviors here.  NOTE: As of 2/23/00 save_story now returns a list!  2 values!  Element 0 is
the $qid/return code, Element 1 is the error message (only if Element 0 is 0)

=back

=cut

sub save_story {
	my $S = shift;
	my $mode = shift || 'full';
	my $parms = $S->{CGI}->Vars;
	my %params;
	foreach my $key (keys %{$parms}) {
		$params{$key} = $parms->{$key};
	}
	my $sid = $params{sid};
	my ($rv, $sth);

	my $currtime = $S->_current_time;
	my $posttype = $params{'posttype'};
	$posttype = "html" if $S->cgi->param('operat') eq 'publish';
	
	# sigh, move authorid over to aid if aid doesn't exist.
	$params{'aid'} ||= $params{'authorid'};
	$parms->{'aid'} ||= $parms->{'authorid'};
	my ($test_ret, $error) = $S->_check_story_validity($sid, $parms);
	unless( $test_ret ) {
		return ($test_ret, $error);
	}
	
	# log it in case of script attack with an account
	my $nick = $S->get_nick_from_uid($S->{UID});
	warn "<< WARNING >> Story posted by $nick with uid=$S->{UID} at $currtime, IP: $S->{REMOTE_IP}   Title: \"$params{title}\"\n" if ($DEBUG);

	# sigh
	my $airtmp = $params{introtext};
	my $abrtmp = $params{bodytext};
	# best stow the old displaystatus here
	my $qdssid = $S->dbh->quote($sid);
	($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'displaystatus',
		FROM => 'stories',
		WHERE => "sid = $qdssid"
		});
	my $olddsp = $params{olddsp} = $sth->fetchrow;
	$sth->finish;

	if ($mode ne 'full') {
		
		unless ($S->have_perm('story_displaystatus_select')) {
			$params{writestatus} = -2;
			if ($params{edit_in_queue}) {
				$params{displaystatus} = -3;
			} else {
				$params{displaystatus} = -2;
				$params{timeupdate} = 'now';
				$S->move_story_to_voting($sid);
			}
		}
		
		if ($params{section} eq 'Diary' && !$S->have_perm('story_displaystatus_select')) {
			$params{displaystatus} = 1;
		}
		
		unless ($S->have_perm('story_commentstatus_select')) {
			$params{comment_status} = $S->{UI}->{VARS}->{default_commentstatus};
			$params{comment_status} ||= $S->dbh->quote('0');
		}

		my $filter_errors;
		$params{introtext} = $S->filter_comment($params{introtext}, 'intro', $posttype);
		$filter_errors = $S->html_checker->errors_as_string;
		return (0, $filter_errors) if $filter_errors;

		$params{bodytext} = $S->filter_comment($params{bodytext}, 'body', $posttype);
		$filter_errors = $S->html_checker->errors_as_string;
		return (0, $filter_errors) if $filter_errors;

		$params{title} = $S->filter_subject($params{title});
		$params{dept} = $S->filter_subject($params{dept});

		# one more constraint on posting: title length
		# if it's more than 100 (the db field size), don't let them post
		if (length($params{title}) > 100) {
			return (0, 'Please choose a shorter title.');
		}
		# and make sure we have tags
		if($S->var('use_tags') && $S->var('require_tags') && $S->cgi->param('operat') ne 'draft'){
			return (0, 'Please include at least one tag with your story.') unless $params{tags};
			}
		} 
#	elsif ($mode eq 'full' && !$S->have_perm('story_admin') && !$S->cgi->param('operat')) {
	# try it this way, maybe?
	elsif ($mode eq 'full' && !$S->cgi->param('operat') && $S->cgi->param('preview') eq 'Publish'){
		my $filter_errors;
		$params{introtext} = $S->filter_comment($params{introtext}, 'intro', $posttype);
                $filter_errors = $S->html_checker->errors_as_string;
                return (0, $filter_errors) if $filter_errors;

		$params{bodytext} = $S->filter_comment($params{bodytext}, 'body', $posttype);
                $filter_errors = $S->html_checker->errors_as_string;
                return (0, $filter_errors) if $filter_errors;

		$params{title} = $S->filter_subject($params{title});
                $params{dept} = $S->filter_subject($params{dept});

		# one more constraint on posting: title length
                # if it's more than 100 (the db field size), don't let them post
		if (length($params{title}) > 100) {
                        return (0, 'Please choose a shorter title.');
                	}
		# and make sure we have tags
                if($S->var('use_tags') && $S->var('require_tags') && $S->cgi->param('operat') ne 'draft'){
                        return (0, 'Please include at least one tag with your story.') unless $params{tags};
                        }
		} 
	elsif ($mode eq 'full' && !$S->cgi->param('operat') && $S->cgi->param('preview') eq 'Preview'){
		# pretty sure we won't have to do nearly so much here.
		# At least, though, we'll need to blank out the intro and body
		# text fields.
		$params{introtext} = $params{bodytext} = '';
		}
	else {
		# check to see if story is moving out of edit queue
		if ($sid && ($params{displaystatus} != -3) && ($S->_check_story_mode($sid) == -3)) {
			$S->move_story_to_voting($sid);
		}
		unless ($S->have_perm('story_displaystatus_select')) {
			$params{'displaystatus'} = $S->_check_story_mode($sid)
		}
	}
	
	my $draft;
	# special ajax story displaystatus stuff
	if($params{operat}){
		# if we're using the story editor, then we already have
		# a sid and whatnot, so we can get stuff from there
		my $sd = $S->story_data_arr([$sid]);
		my $ds = $sd->[0]->[11];
		my $stime = $sd->[0]->[5];
		# interesting. Apparently, the ajax form doesn't actually
		# send the timestamp in the form. That's really probably
		# for the best. In any case, we probably ought to set it
		# here specifically, and update it if we're publishing for
		# the first time. The "now" thing gets caught later.
		if ($params{operat} eq 'draft') {
			#warn "Surely, we're here: ds: $ds\n";
			$params{displaystatus} = $ds;
			# set the draft status too
			$draft = 1;
			# and time.
			$params{time} = $stime;
			}
		elsif ($params{operat} eq 'movq'){
			$params{displaystatus} = ($ds == -4) ? -5 : -4;
			$draft = 1;
			$params{time} = $stime;
			}
		elsif ($params{operat} eq 'publish'){
			if ($params{section} eq 'Diary' && !$S->have_perm('story_displaystatus_select')){
				# set displaystatus as appropriate
				$params{displaystatus} = ($ds == -4) ? 1 : $ds;
				}
			$draft = 0;
			$params{time} = ($ds == -4 || $ds == -5) ? $currtime : $stime;
			# Set time to $stime if we're scheduling.
			if($params{reallySched} && $params{scheduleDate} && $params{scheduleTime} && $S->have_perm('story_sched')){
				$params{time} = $stime;
				}
			if($S->have_perm('story_admin') && !$S->have_perm('story_sched') && $S->is_scheduled($sd->[0]->[26])){
                                $params{displaystatus} = $ds;
                                }
			my $filter_errors;
                	$params{introtext} = $S->filter_comment($params{introtext}, 'intro', $posttype);
                	my $introerr = $S->html_checker->errors_as_string;
			$filter_errors = qq|<div id="introErrors">$introerr</div>| if $introerr;

                	$params{bodytext} = $S->filter_comment($params{bodytext}, 'body', $posttype);
                	my $bodyerr = $S->html_checker->errors_as_string;
			$filter_errors .= qq|<div id="bodyErrors">$bodyerr</div>| if $bodyerr;

                	$params{title} = $S->filter_subject($params{title});
                	$params{dept} = $S->filter_subject($params{dept});

               	 	# one more constraint on posting: title length
                	# if it's more than 100 (the db field size), don't let them post
	                if (length($params{title}) > 100) {
                        	$filter_errors .= qq|<div id="titleErrors">Please choose a shorter title.</div>|;
                        	}
			if($filter_errors){
				return (0, $filter_errors);
				}
			}
		else {
			warn "Undefined story operation\n";
			return 0, "Undefined story editor operation.\n";
			}
		}
	else {
		$draft = 0;
		}
		
	
	my $update = "<strong>Update [$currtime by $S->{NICK}]:</strong>";
	my $editorsnote = "<strong>[editor's note, by $S->{NICK}]</strong>";
	foreach (qw(introtext bodytext)) {
		$params{$_} =~ s/\[UPDATE\]/$update/g;
		$params{$_} =~ s/\[ED\]/$editorsnote/g;
	}

	# if using macros, and 'render on save' is on, then render the macro(s) before saving.
	# Render both introtext and bodytext.

	my $introtext = $params{introtext};	
	my $bodytext = $params{bodytext};

	if (exists($S->{UI}->{VARS}->{use_macros}) && $S->{UI}->{VARS}->{use_macros}
		&& defined($S->{UI}->{VARS}->{macro_render_on_save})
		&& $S->{UI}->{VARS}->{macro_render_on_save}) {
		$introtext = $S->process_macros($introtext,'intro');
		$bodytext = $S->process_macros($bodytext,'body');
	}

	$introtext = $S->{DBH}->quote($introtext);
	$bodytext = $S->{DBH}->quote($bodytext);	

	my $title = $S->{DBH}->quote($params{title});
	# for versioning
	my $raw_title = $params{title};
	my $dept = $S->{DBH}->quote($params{dept});
	my $section = $S->{DBH}->quote($params{section});
	my $q_sid = $S->{DBH}->quote($sid);
	# For some reason known only to god and his angels, sometimes the
	# section gets blanked, and bad things happen. This is an effort
	# to insure that that doesn't happen.
	if(!$params{section}){
		my ($rv0, $sth0) = $S->db_select({
			WHAT => 'section',
			FROM => 'stories',
			WHERE => "sid = $q_sid"
			});
		#  last ditch effort to grab it from the existing entry
		#  before it gets blown away
		$section = $sth0->fetchrow;
		$sth0->finish;
		# and if it's *still* null, fuck it and assign 'Diary'
		$section = 'Diary' unless $section;
		$section = $S->dbh->quote($section);
	    	}
	my $edit_category = $params{edit_category} || 0;
	my $commentstatus = $params{comment_status} || 0;
	my $time = $params{time};
	my $auth_intro = $S->cgi->param('introraw') || $airtmp;
	my $auth_body = $S->cgi->param('bodyraw') || $abrtmp;
	# need to make sure the raw stuff gets updates and eds processed
	foreach ($auth_intro, $auth_body){
		$_ =~ s/\[UPDATE\]/$update/g;
		$_ =~ s/\[ED\]/$editorsnote/g;
		}
	# we need the raw author intro and body for versioning
        my $raw_ai = $auth_intro;
        my $raw_ab = $auth_body;
	$auth_intro = $S->dbh->quote($auth_intro);
	$auth_body = $S->dbh->quote($auth_body);
	if ($params{timeupdate} eq 'now' || $time eq '') {
		$time = $currtime;
	}
	#if($S->have_perm('edit_own_diary') && $params{op} eq 'diary_edit'){
	# gotta treat it slightly differently
	# if operat is defined, we've already done displaystatus checking
	my $limits;
	if($S->have_perm('edit_own_diary') && !$S->have_perm('story_admin') && !$S->cgi->param('operat')){
		# sigh. Looks like we need to check for this.
		my($rv, $sth) = $S->db_select({
			WHAT => 'displaystatus',
			FROM => 'stories',
			WHERE => "sid = '$sid'"});
		my $r = $sth->fetchrow_hashref;
		$sth->finish;
		if ($S->cgi->param('preview') eq 'Publish'){
			#$params{displaystatus} = ($r->{'displaystatus'} == -4) ? 1 : $r->{'displaystatus'};
			# Are we publishing this story for the first time?
			if($r->{'displaystatus'} == -4) {
				if ($S->{UI}->{VARS}->{'use_hard_story_limit'} && !$S->have_perm('evade_story_hard_limit')){
					# what have we posted, exactly?
					my ($rv2, $sth2) = $S->db_select({
						WHAT => 'count(*)',
						FROM => 'stories',
						WHERE => "(TO_DAYS(NOW()) - TO_DAYS(time) < 1) AND aid = $S->{UID} AND displaystatus >= -1 AND title != 'untitled diary'"
						});
					my $storynum = $sth2->fetchrow();
					$sth2->finish;
					if ($storynum > $S->{UI}->{VARS}->{'hard_story_limit'}){
						my $dplural = ( $S->{UI}->{VARS}->{'hard_story_limit'} == 1) ? 'y' : 'ies';
						$limits = "Sorry, you can only post $S->{UI}->{VARS}->{'hard_story_limit'} diar$dplural on this site per day. Your diary has been saved as a draft, and you can publish it tomorrow.";
						$params{displaystatus} = -4;
						}
					else {
						$params{displaystatus} = 1;
						}
					}
				else {
					$params{displaystatus} = $r->{displaystatus};
					}
				}
			else {
				$params{displaystatus} = $r->{displaystatus};
				}
			}
		else {
			$params{displaystatus} = $r->{'displaystatus'};
			}
		#$params{displaystatus} = 1;
		}
	if(!$S->have_perm('story_admin')){
		$params{aid} = $S->{UID};
		}

	# grrrrrrrrrr. stupid fucking raw intro and body shit.
	my $textupdate = ($S->cgi->param('operat') eq 'draft' || $S->cgi->param('operat') eq 'movq' || $S->cgi->param('preview') eq 'Preview') ? qq|author_intro=$auth_intro, author_body=$auth_body| : qq|introtext=$introtext, bodytext=$bodytext|;
	# grrr x 2
	#if ($params{displaystatus} == -4 && $S->cgi->param('preview') eq 'Preview') {
	if($S->cgi->param('preview')){
		$textupdate = qq|author_intro=$auth_intro, author_body=$auth_body, introtext=$introtext, bodytext=$bodytext|;
		}
	my $titleupdate;
	if($S->cgi->param('operat')){
		if ($S->cgi->param('operat') eq 'draft'){
			$titleupdate = "author_title = $title";
			}
		else {
			$titleupdate = "title = $title, author_title = $title";
			}
		}
	else {
		if($S->cgi->param('preview') eq 'Preview' || $S->cgi->param('preview') eq 'preview'){
			$titleupdate = "author_title = $title";
                        }
                else {
                        $titleupdate = "title = $title, author_title = $title";
                        }
		}
	# Schedule, if need be
	if($S->have_perm('story_sched')){
       		if($params{reallySched} && $params{scheduleDate} && $params{scheduleTime}){
                	my ($suc, $smsg) = $S->schedule_post(\%params);
                        unless ($suc) {
                        	return (0, $smsg);
                               }
                        }
                else {
                        # deschedule anything that we're not
                        # scheduling.
                        $S->deschedule_post(\%params);
                        }
		}
	# Question: are we publishing this story for the first time? If so,
	# check and see if we need a new sid
	my $upsid;
	if(($olddsp == -4 || $olddsp == -5) && $params{displaystatus} >= 0){
		# first check and see if we're trying to publish an archived
		# story for the first time, and bail if so.
		if($S->_check_archivestatus($sid)){
			return (0, "Sorry, you were trying to publish a draft that has passed into the archive, and you can't do that. However, you may copy the contents of this diary and paste it into a new one. You may want to delete this diary afterwards.");
			}
		($rv, $sth) = $S->db_select({
			WHAT => 'TO_DAYS(NOW()) - TO_DAYS(time)',
			FROM => 'stories',
			WHERE => "sid = $q_sid"
			});
		my $age = $sth->fetchrow;
		$sth->finish;
		if ($age != 0){
			$upsid = $S->make_new_sid();
			# Interesting. Looks like it might be easiest
                        # to update the sid here. That way, we just have
                        # to do the update again a little further down and not
                        # have to worry about the changed story params.
                        my $nk;
                        ($sid, $nk) = $S->update_sid($sid, $upsid);
                        $q_sid = $S->dbh->quote($sid);
                        if(!$sid){ # eeep! Transaction failed
                                return (0, "Sorry, you were saving a story that
had the sid changed, and something went wrong doing so. This isn't a huge proble
m, but your story hasn't published. Just try again.");
                                }
			}
		}

	if ($sid && $sid ne '') {
		($rv, $sth) = $S->db_update({
			DEBUG => 0,
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT => 'stories',
			SET => qq|tid='$params{tid}',
			 aid=$params{aid},
			 $titleupdate, 
			 dept=$dept, 
			 time='$time', 
			 $textupdate,
			 edit_category=$edit_category,
			 section=$section, 
			 displaystatus=$params{displaystatus}, 
			 commentstatus=$commentstatus,
			 goatse_draft=$draft|,
			WHERE => qq|sid = $q_sid|});
		# let's do the old switch-a-roo
		$sid = $upsid if $upsid;
		$S->save_story_version($sid, $raw_title, $raw_ai, $raw_ab);
		$S->run_hook('story_update', $sid, $limits);
		# just clear the id/sid cache if the displaystatus changed,
		# methinks
	        my $cfetch;
                if($olddsp == 0 || $params{displaystatus} == 0){
                        $cfetch = "main";
                        }
                elsif ($olddsp == 1 || $params{displaystatus} == 1){
                        $cfetch = "section";
                        }
                for (my $i = 1; $i < 5; $i++){
                        $S->cache->remove("${cfetch}-${i}_15");
                        }
	} else {
		# With the new stuff, we should *never* be able to get here.
		# If we do, bail and return an error.
		return (0, "Somehow we got to this point without a sid, which we shouldn't be able to ever do with the new system. Please reload your draft, which should fix the problem. If it doesn't, use the Contact form to let us know about the problem.");
		$sid = $S->make_new_sid();
	
		if( $params{op} eq 'submitstory' && $params{section} ne 'Diary' && $S->{UI}->{VARS}->{post_story_threshold} == 0 ) {
			$params{displaystatus} = "0";
			$params{writestatus} = "0";
		}

		# don't want to automatically auto-post if its an admin editing a story or something
		unless( $params{op} eq 'admin' ) {
			if( $S->have_section_perm('autofp_post_stories', $params{section}) ) {
				$params{displaystatus} = "0";
			} elsif( $S->have_section_perm('autosec_post_stories', $params{section}) ) {
				$params{displaystatus} = "1";
			}
			
		}
		
		$time = $currtime;
		my $q_sid = $S->dbh->quote($sid);
		my $q_tid = $S->dbh->quote($params{tid});
		($rv, $sth) = $S->db_insert({
			DEBUG => 0,
			INTO => 'stories',
			COLS => 'sid, aid, title, dept, time, introtext, bodytext, section, displaystatus, commentstatus, edit_category',
			VALUES => qq|$q_sid, $params{aid}, $title, $dept, '$time', $introtext, $bodytext, $section, $params{displaystatus}, $commentstatus, $edit_category|});

		$S->run_hook('story_new', $sid, $title, $introtext, $bodytext, $section);
	}
	$sth->finish;


	# Save story tags, if we're using them
	if ($S->var('use_tags')) {
		$S->save_tags($sid, $params{'tags'});
	}

	# don't try to write a poll if they aren't allowed to 
	# they must have attach_poll perms
	my $ph = $S->get_poll_hash($S->{CGI}->param('qid'));
        my $up = $ph->{unpublished};
	if( $S->{CGI}->param('qid') && $S->have_perm( 'attach_poll' ) && ($up || $S->have_perm('story_admin')) ) {
		# try to write the poll
		my $eiq = $S->cgi->param('edit_in_queue') || $S->update_own_poll($sid);
		$S->write_attached_poll($sid, $eiq );
	}

	if ($rv) {
		# Mark the story modified in the cache
		my $time = time();
		my $r = $sid.'_mod';
		$S->cache->stamp_cache($r, $time);
		$S->story_cache->del($sid);
		$S->story_cache->asd_del($sid);
		$S->story_cache->del_arr($sid);
		$S->story_cache->asd_del_arr($sid);
		delete $S->{STORY_CACHE}->{$sid};
		delete $S->{STORY_CACHE}->{$sid};
		$S->cache->remove("kurl_" . $S->get_story_id_from_sid($sid));
		# be doubly fucking sure
		$S->cache->remove("s_sid_f_id_" . $S->get_story_id_from_sid($sid));
		# let's try updating the serial here
		$S->update_serial($sid);
		# throw a small thing in
		return (0, $limits) if $limits;
		return ($sid, "Story $sid saved");
	} else {
		return (0, "There was an error saving your story. It was not saved -- $sid - $section - $params{displaystatus} - $params{'op'} - rv: $rv $DBI::errstr");
	}
	
}

sub edit_story_form {
	my $S = shift;
	my $form_values;
	my $mode = shift || 'full';
	my $sid = 	$S->{CGI}->param('sid');
	my $eiq = $S->cgi->param('edit_in_queue');
	my $confirm_cancel = $S->cgi->param('confirm_cancel');
	my ($story_mode, $stuff) = $S->_mod_or_show($sid);
	$sid = '' if ( ($confirm_cancel && $eiq) || $S->cgi->param('delete') );

	if ( ($sid ne '') && ($story_mode ne 'edit') )  {
	unless ( $S->have_perm('story_admin') || $S->have_perm('edit_own_diary') || $S->have_perm('edit_my_stories')) {return "<P><B>Story ($sid) cannot be edited because it is currently in $story_mode mode.</B></P>"; }
	}
	my $params = $S->{CGI}->Vars;
	my $story_data;
	my $scon = $S->goddamned_grip_of_controls($sid);

	if ($S->{CGI}->param('file_upload')) {
		my $file_upload_type=$S->{CGI}->param('file_upload_type');
		my ($return, $file_name, $file_size) = $S->get_file_upload($file_upload_type);
		if ($file_upload_type eq 'content') {
		#replace content with uploaded file
			$S->param->{bodytext} = $return unless $file_size ==0;
		} else {
			# $return should be empty if we are doing a file upload, if not they are an error message
			return (0, $return) unless $return eq '';
		}
	}

	$form_values->{allowed_html_intro} = $S->html_checker->allowed_html_as_string('intro')
		if $mode ne 'full' && (!$S->{UI}->{VARS}->{hide_story_allowed_html});
	$form_values->{allowed_html_body} = $S->html_checker->allowed_html_as_string('body')
		if $mode ne 'full' && (!$S->{UI}->{VARS}->{hide_story_allowed_html});

	
	if ($mode eq 'full') {
		$form_values->{notes} = $S->{UI}->{BLOCKS}->{story_edit_notes};
	}
	
	if ($params->{delete}) {
	  	if ($params->{confirm_cancel}) {
			$S->story_post_write('-1', '-1', $S->{CGI}->param('sid'));
			return '<P><B>Story cancelled.</B></P>'; }
		else {
			return '<P><B>"Confirm cancel" check box was not selected, the story will not be cancelled.</B></P>';}
	
	}
	
	if ($params->{preview} || $mode eq 'Save Error') {
			$story_data = $params;
	} elsif ($sid && $mode eq 'full') {
		my $qsid = $S->dbh->quote($sid);
		my ($rv, $sth) = $S->db_select({
		 		ARCHIVE => $S->_check_archivestatus($sid),
				WHAT => '*',
				FROM => 'stories',
				WHERE => qq|sid = $qsid|});
		$story_data = $sth->fetchrow_hashref;
		$sth->finish;
	}
	
	$form_values->{tid} = $S->{CGI}->param('tid') || $story_data->{tid};
	$form_values->{section} = $S->{CGI}->param('section') || $story_data->{section};
	$form_values->{parent} = $S->cgi->param('parent_section') || '';
	$form_values->{topic_select} = $S->topic_select($form_values->{tid});
	$form_values->{topic_select} = qq|<input type="hidden" name="tid" value="$form_values->{tid}">| unless ($form_values->{topic_select});
	#$form_values->{section_select} = $S->section_select($form_values->{parent}, $form_values->{section});
	$form_values->{section_select} = $scon->{section};
	
	my ($del_button, $archive_button);
	
	$form_values->{displaystatus_select} = $S->displaystatus_select($story_data->{displaystatus}) 
		if ($S->have_perm('story_displaystatus_select'));
	
	$form_values->{commentstatus_select} = $S->commentstatus_select($story_data->{commentstatus})
		if ($S->have_perm('story_commentstatus_select'));
	
	if ($mode eq 'full') {
		if ($S->{UI}->{VARS}->{use_edit_categories} ) {
			$form_values->{edit_category_select} = $S->edit_category_select($story_data->{edit_category});}
		#Not deleting this line quite yet in case someone needs it
		#$writestatus_select = $S->writestatus_select($story_data->{writestatus});
		#$form_values->{displaystatus_select} = $S->displaystatus_select($story_data->{displaystatus}) if ($S->have_perm('admin_story') || $S->have_perm('story_displaystatus_select'));
		$form_values->{displaystatus_select} = $scon->{displaystatus};
		# maybe this will work.
		$form_values->{displaystatus_select} = '' if ($S->cgi->param('op') eq "diary_edit");
		#$form_values->{commentstatus_select} = $S->commentstatus_select($story_data->{commentstatus}) if $S->have_perm('story_commentstatus_select');
		$form_values->{commentstatus_select} = $scon->{commentstatus};
		$form_values->{postmode_select} = $S->_postmode_option_form();
		if ($sid) {
			my $delcheck = ($S->cgi->param('delconf')) ? ' CHECKED' : '';
			$del_button = qq|
				<INPUT TYPE="submit" NAME="delete" VALUE="Delete"> &nbsp; <input type="checkbox" name="delconf" value="1"$delcheck> Confirm Deletion &nbsp;|;
			$archive_button = (($S->cgi->param('op') eq 'diary_edit') || !$S->have_perm('story_admin')) ? '' : qq|
				<INPUT TYPE="submit" NAME="archive" VALUE="Archive">&nbsp;| if $S->{HAVE_ARCHIVE} && (!$S->_check_archivestatus($sid));

		}
	} else {
		$form_values->{postmode_select} = $S->_postmode_option_form();	
	}
	
	if ($mode eq 'full') {
		$form_values->{all_buttons} = qq|
			<INPUT TYPE="submit" NAME="preview" VALUE="Preview">&nbsp;
			<INPUT TYPE="submit" NAME="preview" VALUE="Publish">&nbsp;
			$del_button
			$archive_button|;
	} else {
		$form_values->{all_buttons} = qq|
			<INPUT TYPE="submit" NAME="preview" VALUE="Preview">&nbsp;|;
		if ($params->{preview} || $S->var('require_story_preview') == 0 ) {
			$form_values->{all_buttons} .= qq|	
			<INPUT TYPE="submit" NAME="save" VALUE="Submit">&nbsp;|;
			if ( $S->have_perm('edit_own_story') ) {
				$form_values->{all_buttons} .= $del_button;
			}
		}
	}
			
	$form_values->{aid} = $story_data->{aid} || $S->{UID};
	my $tool = '';
	
	if ($mode eq 'full') {
		$tool = qq|<INPUT TYPE="hidden" NAME="tool" VALUE="story">|;
	}
	my $event;
	if ( my $eid = $S->cgi->param('event') ) {
		$event = qq|<INPUT type="hidden" name="event" value="$eid">|;
	}
	my $formkey = $S->get_formkey_element();
 	
	$form_values->{upload_page} = $S->{UI}->{BLOCKS}->{story_edit_upload};
	my $upload_form = $S->display_upload_form(0, 'content');
	$form_values->{upload_page} =~ s/%%form%%/$upload_form/g;		
	
	$form_values->{hidden_form_data} = qq|
		%%submit_include_top%%
		<INPUT TYPE="hidden" NAME="op" VALUE="$params->{op}">
		$tool
		<INPUT TYPE="hidden" NAME="sid" VALUE="$sid">
		<INPUT TYPE="hidden" NAME="aid" VALUE="$form_values->{aid}">
		$event
		$formkey
		<INPUT TYPE="hidden" NAME="time" VALUE="$story_data->{time}">|;

	
#	$story_data->{title} =~ s/"/&quot;/g;
	if ($story_data->{title} eq 'untitled diary'){
		$story_data->{title} = $params->{title} || $story_data->{author_title};
		}
	$story_data->{title} = $S->comment_text($story_data->{title});
	$story_data->{title} =~ s/"/&quot;/g;

	$form_values->{title} = $story_data->{title} || $params->{title};

	if ($S->{UI}->{VARS}->{show_dept}) {
		$form_values->{dept} = $S->{UI}->{BLOCKS}->{story_edit_dept};
		$form_values->{dept} =~ s/%%dept%%/$story_data->{dept}/g;
	}

	if ($S->var('use_tags')) {
		$form_values->{tags} = $S->story_tag_field();
	}
		
	if ($S->spellcheck_enabled()) {
		# We will only have a formkey if they have already used the submit form.
		# We only want to set the default spellcheck the first time they submit
		# We don't want to override the setting.

		$params->{spellcheck} = $S->pref('spellcheck_default') unless ($S->{CGI}->param('formkey'));
		my $check = ($params->{spellcheck} eq 'on') ? ' CHECKED' : '';
		$form_values->{spellcheck} = $S->{UI}->{BLOCKS}->{story_edit_spellcheck};
		$form_values->{spellcheck} =~ s/%%check%%/$check/g;
	}
	
	# show edit in queue checkbox only if the var is set and the mode is normal (non-admin)
 	if ( ($S->have_perm('edit_own_story')) && ($mode ne 'full') && ($params->{section} ne 'Diary')){
 		my $check =  $params->{'preview'} ? 
		             ($params->{edit_in_queue} ? ' CHECKED' : '') 
					 : ' CHECKED';
		$form_values->{edit_queue} = $S->{UI}->{BLOCKS}->{story_edit_editqueue};
		$form_values->{edit_queue} =~ s/%%check%%/$check/g;
 	}
	
	if ($S->have_perm('story_time_update')) {
		my $check = ' CHECKED' if ($params->{timeupdate} eq 'now');
		$form_values->{time_update} = $S->{UI}->{BLOCKS}->{story_edit_timeupdate};
		#$form_values->{time_update} =~ s/%%check%%/$check/g;
		$form_values->{time_update} = $scon->{timecon};

	}
	
	if ($mode eq 'full') {	
		$form_values->{update_txt} = $S->{UI}->{BLOCKS}->{story_edit_updatetxt};
		$form_values->{edit_txt}   = $S->{UI}->{BLOCKS}->{story_edit_edittxt};
	}

	foreach (qw(introtext bodytext)) {
		$story_data->{$_} = $S->comment_text($story_data->{$_});
	}

	$form_values->{textarea_cols} = $S->pref('textarea_cols'); 
	$form_values->{textarea_rows} = $S->pref('textarea_rows'); 

	#my $sd = $S->story_data_arr([$sid]);
	$form_values->{introtext} = $params->{introtext} || $story_data->{author_intro};
	$form_values->{bodytext} = $params->{bodytext} || $story_data->{author_body}; 
	#undef $sd;

	# if they can attach polls generate the form
	if( $S->have_perm( 'attach_poll' ) ) {
		$form_values->{poll_message} = $S->{UI}->{BLOCKS}->{attach_poll_message};
	
		# if they are previewing pass the args to the function.  else give them the real story $sid
		if($params->{preview} && !$params->{retrieve_poll}) {
			$form_values->{poll_form} = $S->make_attached_poll_form('preview', $params);
		} else {
			$form_values->{poll_form} .= $S->make_attached_poll_form('normal', $sid);
		}
	}
	
	if ($mode ne 'full') {
		$form_values->{guidelines} = $S->{UI}->{BLOCKS}->{submission_guidelines};
	}
	$form_values->{guidelines} = $S->{UI}->{BLOCKS}->{diary_guidelines} if $form_values->{section} eq 'Diary';
	
	my $content = $S->interpolate($S->{UI}->{BLOCKS}->{edit_story_form}, $form_values);
		
	return $content;
}
	
sub topic_select {
	my $S = shift;
	my $tid = shift;
	my $selected= '';
	
	return '' unless $S->{UI}->{VARS}->{use_topics};
	
	# Check for diary
	my $section = $S->{CGI}->param('section');
	my $sid = $S->{CGI}->param('sid');
	if (!$S->{UI}->{VARS}->{diary_topics}) {
		if ($S->have_perm('story_admin') && $sid) {
			warn "SID is $sid\n" if $DEBUG;
			my $stories = $S->story_data_arr([$sid]);
			my $story = $stories->[0];
			if ($story->[1] && $story->[10] eq 'Diary') {
				warn "Topic is $story->[1]\n" if $DEBUG;
				return qq|<INPUT TYPE="hidden" NAME="tid" VALUE="$tid"><B>[ $story->[1]</B>|;
			}
		} elsif ($section eq 'Diary') {
			return qq|<INPUT TYPE="hidden" NAME="tid" VALUE="diary"><B>[ $S->{NICK} ]</B>|;
		}
	}
	
	my $topic_select = qq|
		<SELECT NAME="tid" SIZE=1>
	|;
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'tid, alttext',
		FROM => 'topics',
		ORDER_BY => 'tid asc'});
	if ($rv ne '0E0') {
		while (my $topic = $sth->fetchrow_hashref) {
			next if (($topic->{tid} eq 'diary') && (!$S->{UI}->{VARS}->{diary_topics}));

			if (($topic->{tid} eq $tid) || (($tid eq '') && ($topic->{tid} eq 'diary') && ($section eq 'Diary'))) {
				$selected = ' SELECTED';
			} else {
				$selected = '';
			}
			$topic_select .= qq|
				<OPTION VALUE="$topic->{tid}"$selected>$topic->{alttext}|;
		}
	}
	$sth->finish;
	
	$topic_select .= qq|
		</SELECT>&nbsp;|;
	return $topic_select;
}


sub writestatus_select {
	my $S = shift;
	my $stat = shift;
	my $selected= '';
	
	my $status_select = qq|
		<SELECT NAME="writestatus" SIZE=1>
	|;
	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'statuscodes',
		ORDER_BY => 'code asc'});
	if ($rv ne '0E0') {
		while (my $status = $sth->fetchrow_hashref) {
			if ($status->{code} eq $stat) {
				$selected = ' SELECTED';
			} else {
				$selected = '';
			}
			$status_select .= qq|
				<OPTION VALUE="$status->{code}"$selected>$status->{name}|;
		}
	}
	$sth->finish;
	
	$status_select .= qq|
		</SELECT>&nbsp;|;
	return $status_select;
}

sub edit_category_select {
	my $S = shift;
	my $stat = shift;
	my $selected= '';
	
	my $edit_category_select = qq|
		<SELECT NAME="edit_category" SIZE=1>
	|;
	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'editcategorycodes',
		ORDER_BY => 'orderby asc'});
	if ($rv ne '0E0') {
		while (my $status = $sth->fetchrow_hashref) {
			if ($status->{code} eq $stat) {
				$selected = ' SELECTED';
			} else {
				$selected = '';
			}
			$edit_category_select .= qq|
				<OPTION VALUE="$status->{code}"$selected>$status->{name}|;
		}
	}
	$sth->finish;
	
	$edit_category_select .= qq|
		</SELECT>&nbsp;|;
	return $edit_category_select;
}

sub displaystatus_select {
	my $S = shift;
	my $tmpstat = shift; # || $S->{UI}->{VARS}->{default_displaystatus};
	my $stat = (defined($tmpstat))? $tmpstat : $S->{UI}->{VARS}->{default_displaystatus};
	# have to test if $tmpstat is defined; if it's zero (front page) it used the var
	my $selected= '';
	
	my $status_select = qq|
		<SELECT NAME="displaystatus" SIZE=1>
	|;
	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'displaycodes',
		ORDER_BY => 'code asc'});
	if ($rv ne '0E0') {
		while (my $status = $sth->fetchrow_hashref) {
			if ($status->{code} eq $stat) {
				$selected = ' SELECTED';
			} else {
				$selected = '';
			}
			$status_select .= qq|
				<OPTION VALUE="$status->{code}"$selected>$status->{name}|;
		}
	}
	$sth->finish;
	
	$status_select .= qq|
		</SELECT>&nbsp;|;
	return $status_select;
}


sub commentstatus_select {
	my $S = shift;
	my $stat = shift;
	
	my $status_select = qq|
		<select id="comment_status" name="comment_status" size="1">
	|;
	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'commentcodes',
		ORDER_BY => 'code asc'});
	if ($rv ne '0E0') {
		while (my $status = $sth->fetchrow_hashref) {
			my $selected = '';
			my $default = $S->{UI}->{VARS}->{default_commentstatus};
			if (defined($stat) && ($status->{code} == $stat)) {
				$selected = ' selected="selected"';
			} elsif (!defined($stat) && ($status->{code} == $default)) {
				$selected = ' selected="selected"';
			}

			$status_select .= qq|
				<option value="$status->{code}"$selected>$status->{name}</option>|;
		}
	}
	$sth->finish;
	
	$status_select .= qq|
		</select>&nbsp;|;
	return $status_select;
}

sub section_select {
	my $S = shift;
	my $parent = shift;
	my $sec = shift;
	my $selected = '';
	
	#warn "Parent is ($parent), Section is ($sec)\n";
	
	my $op = $S->cgi->param('op');
	
	# Send back a hidden field if it's a diary
	if (($parent eq 'Diary' || $sec eq 'Diary') && !$S->have_perm('story_admin')) {
		my $section = qq|
			<input type="hidden" name="section" id="section" value="Diary" />
			<input type="hidden" name="parent_section" value="Diary" />|;
		$section .= "Post to: <b>[Diary]</b>" if $S->have_perm('story_admin');
		return $section;
	}
	# or an event
	if ( $S->cgi->param('event') ) {
		my $e_section = $S->var('event_story_section');
		my $section = qq|
			<B>[ Event ]</B>
			<INPUT TYPE="hidden" NAME="section" VALUE="$e_section">
			<INPUT TYPE="hidden" NAME="parent_section" VALUE="$e_section">|;
		return $section;
	}
	
	my $section_select = "Post to: ";
	my ($parent_selections, $child_selections, $divider);
	my $section_siblings = {};
	
	if ($S->{UI}->{VARS}->{restrict_story_submit_to_subsect}) {
		if ($op eq 'admin') {

			foreach my $p (sort keys %{$S->{SECTION_DATA}->{$sec}->{parents}}) {
				$parent_selections .= qq|
				<option value="$p">&nbsp;&nbsp;&nbsp;$S->{SECTION_DATA}->{$p}->{title}|;
				
				# While we're at it, get siblings of this section
				$section_siblings = $S->{SECTION_DATA}->{$p}->{children}
			}
			$parent_selections = qq|
				<option value="">----Parents----| . $parent_selections if ($parent_selections);
			
			foreach my $p (sort keys %{$S->{SECTION_DATA}->{$sec}->{children}}) {
				$child_selections .= qq|
				<option value="$p">&nbsp;&nbsp;&nbsp;$S->{SECTION_DATA}->{$p}->{title}|;
			}
			$child_selections = qq|
				<option value="">---Children---| . $child_selections if ($child_selections);
			
			$divider = qq|
				<option value="">--------------| if ($parent_selections || $child_selections);
				
		} else {
			$section_select .= qq|
		<input type="hidden" name="parent_section" value="$parent" />
		<b>[ <a href="/section/$parent">$S->{SECTION_DATA}->{$parent}->{title}</a> ]</b> |;
		}
	}
	
	$section_select .= qq|
		<select name="section" id="section" size="1">
		$parent_selections
		$child_selections
		$divider|;

	# pass get_dis....() a regexp, since more than one match is ok
	my $no_perm_hash = $S->get_disallowed_sect_hash('(norm|autofp|autosec)_post_stories');
	
	# Put the parent section up front, as a choice
	if ($S->{UI}->{VARS}->{restrict_story_submit_to_subsect} && $op eq 'submitstory' && !$no_perm_hash->{ $parent }) {
		my $selected = (!$sec || $parent eq $sec) ? ' selected="selected"' : '';
		$section_select .= qq|
		<option value="$parent"$selected>$S->{SECTION_DATA}->{$parent}->{title}</option>
		|;
	}
	
	#warn "Section is $sec\n";
	foreach my $key ( sort keys %{$S->{SECTION_PERMS}}) {
		next if ($key eq 'events');
		next if ( $no_perm_hash->{ $key } );
		next if ($S->{UI}->{VARS}->{restrict_story_submit_to_subsect} && $op eq 'admin' && !$section_siblings->{$key});
		next if ($S->{UI}->{VARS}->{restrict_story_submit_to_subsect} && $op eq 'submitstory' && !$S->{SECTION_DATA}->{$parent}->{children}->{$key});
		 
		my $section = $S->{SECTION_DATA}->{$key};
			
		$selected = ($section->{section} eq $sec) ? ' selected="selected"' : '';

		$section_select .= qq|
			<option value="$section->{section}"$selected>$section->{title}</option>|;
	}

	$section_select .= qq|
		</select>&nbsp;|;
	return $section_select;
}

sub make_new_sid {
	my $S = shift;
	my $sid = '';

	my $rand_stuff = $S->rand_stuff;
	$rand_stuff =~ /^(.....)/;
	$rand_stuff = $1;
	
	my @date = localtime(time);
	my $mon = $date[4]+1;
	my $day = $date[3];
	my $year = $date[5]+1900;

	$sid = "$year/$mon/$day/$date[2]$date[1]$date[0]/$rand_stuff";
	$sid =~ /(.{1,20})/;
	$sid = $1;

	return $sid;
}

sub _clean_up_db {
	my $S = shift;
	my $sid = shift;

	my %opt2table = (
		comments       => "comments",
		ratings        => "commentratings",
		votes          => "storymoderate",
		poll           => "pollquestions",
                viewed_stories => "viewed_stories"
	);

	foreach my $o (@_) {
		next unless $opt2table{$o};
		
		# if there is an attached poll, delete it
		if( $opt2table{$o} eq 'pollquestions' ) {
 			my $attach_qid = $S->get_qid_from_sid($sid);
			$S->_delete_poll($attach_qid);
			
		} else {    # otherwise just delete the story, comments, and ratings
			my $qsid = $S->dbh->quote($sid);
			my ($rv, $sth) = $S->db_delete({
				DEBUG => 0,
				ARCHIVE => $S->_check_archivestatus($sid),
				FROM => $opt2table{$o},
				WHERE => qq|sid = $qsid|
				});
}
	}
}

sub _story_mod_write {
	my $S = shift;
	my $sid = shift;
	return unless ($S->_check_story_mode($sid) <= -2);
	
	my $save = $S->{CGI}->param('save');
	return unless $save;
	
	my $check_vote = $S->_check_vote;
	return if $check_vote;
	
	# MAke sure they came from a vote form!
	my $fk = $S->check_vote_formkey();
	return unless ($fk);
	
	my $vote = $S->{CGI}->param('vote');
	my $s_o = 'X';

	if( $vote == 2 ) {
	    $s_o = 'Y';
	} elsif ( $vote == 1) {
		$s_o = 'N';
	}

	if ($vote > 0) {
		$vote = 1;
	} elsif ($vote < 0) {
		$vote = -1;
	}

	# this doesn't appear to be used anymore
	#my $comment = $S->{CGI}->param('comments');
	#$comment = $S->filter_comment($comment);
	#my $filter_errors = $S->html_checker->errors_as_string;
	#return $filter_errors if $filter_errors;
	#$comment = $S->{DBH}->quote($comment);
	
	$S->save_vote($sid, $vote, $s_o);

	$S->run_hook('story_vote', $sid, $S->{UID}, $vote, $s_o);

	my $message;
	if ( $S->{CGI}->param('mode') eq 'spam' ) {
		# mark the spam vote if it occurred
		$message = $S->{UI}->{BLOCKS}->{story_spam_vote_msg};
		$S->_update_story_votes($sid, $vote);
		$S->_spam_check_story($sid);
	} else {
		# update the story record, eh?
		my ($curr_votes, $curr_score) = $S->_update_story_votes($sid, $vote);
		$message = $S->{UI}->{BLOCKS}->{story_vote_msg};
		$message =~ s/%%vote%%/$vote/g;
		$message =~ s/%%curr_score%%/$curr_score/g;
		
		$message .= $S->_post_story($sid);
	}
	return $message;
}

sub save_vote {
	my $S = shift;
	my $sid = shift;
	my $vote = shift; #value of the vote
	my $s_o = shift;  #vote for section, or front page
	
	my $uid = $S->{UID};
	my $time = $S->_current_time;

	my $check_vote = $S->_check_vote;
	return if $check_vote;
	
	# save the vote itself
	my ($rv, $sth) = $S->db_insert({
		INTO => 'storymoderate',
		COLS => 'sid, uid, time, vote, section_only',
		VALUES => "'$sid', '$uid', '$time', '$vote', '$s_o'"});
	$sth->finish;
	
}
		

sub _check_vote {
	my $S = shift;
	my $uid = $S->{UID};
	my $sid = $S->dbh->quote($S->{CGI}->param('sid'));
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'uid',
		FROM => 'storymoderate',
		WHERE => qq|uid = $uid AND sid = $sid|});
	$sth->finish;
	
	if ($rv == 0) {
		return 0;
	} else {
		return 1;
	}
}

sub check_vote_formkey {
	my $S = shift;
	my $key = $S->{CGI}->param('formkey');
	
	my $user = $S->user_data($S->{UID});
	Crypt::UnixCrypt::crypt($user->{'realemail'}, $user->{passwd}) =~ /..(.*)/;	
	
	return 1 if ($key eq $1);
	return 0;
}

sub _update_story_votes {
	my $S = shift;
	my ($sid, $vote) = @_;
	my ($rv, $sth);
	
	$vote = int $vote;
	
	#warn "Vote is $vote";
	
	if ($vote || $vote == 0) {
			my $q_sid = $S->dbh->quote($sid);
			($rv, $sth) = $S->db_update({
			DEBUG => 0,
			WHAT => 'stories',
			SET => qq|totalvotes = (totalvotes + 1), score = (score + $vote)|,
			WHERE => qq|sid = $q_sid|});
		$sth->finish;
}
	
	my ($newvotes, $newscore) = $S->_get_total_votes($sid);
	#warn "Total is now $newvotes";
	
	return ($newvotes, $newscore);
}	

sub _get_total_votes {
	my $S = shift;
	my $sid = shift;
	my $q_sid = $S->dbh->quote($sid);
	
	my ($rv, $sth) = $S->db_select({
		DEBUG => 0,
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'totalvotes, score',
		FROM => 'stories',
		WHERE => qq|sid = $q_sid|});
	
	my $votes = $sth->fetchrow_hashref;
	$sth->finish;
	my $newvotes = $votes->{totalvotes};
	my $score = $votes->{score};
	
	return ($newvotes, $score);
}	

sub _get_story_userviews {
	#returns the number of unique users that have viewed the story
	#this was directly 'borrowed' Andrew Hurst's story_count box in the Scoop box exchange
	
	my $S = shift;
	my $sid = shift;
	
	my ($rv, $sth) = $S->db_select({
		FROM	=> 'viewed_stories',
		WHAT	=> 'count(uid) as c',
		WHERE	=> "sid = '$sid'"
	});

	my $count = 0;

	if ( $rv ) {
		my $r = $sth->fetchrow_hashref;
		$count = $r->{c};
	}
	$sth->finish();
	return $count;
}

sub _get_user_voted {
	#return the count of votes that the $uid has voted for $sid

	my $S = shift;
	my ($uid, $sid) = @_;
	
	my ($rv, $sth) = $S->db_select({
		FROM	=> 'storymoderate',
		WHAT	=> 'count(vote) as v',
		WHERE   => "sid='$sid' AND uid='$uid'"
	});

	my $count = 0;

	if ( $rv ) {
		my $r = $sth->fetchrow_hashref;
		$count = $r->{v};
	}
	$sth->finish();
	return $count;
}

sub _spam_check_story {
	my $S = shift;
	my $sid = shift;

	return unless $S->{UI}->{VARS}->{use_anti_spam};

	# Double check story's current status
	# Don't want to run this unless it's in edit
	my ($dstat, $wstat) = $S->_check_story_status($sid);
	return unless ($dstat == -3);

	my $votes_threshold = $S->{UI}->{VARS}->{spam_votes_threshold};
	my $spam_percent 	= $S->{UI}->{VARS}->{spam_votes_percentage};
	
	my ($spam_votes, $dummy)= $S->_get_total_votes($sid);
	if ($spam_votes >= $votes_threshold) {
		my $page_userviews	= $S->_get_story_userviews($sid);
		
		if ( ($spam_votes / $page_userviews) > $spam_percent ) {
			$S->move_story_to_voting($sid);	
		}
	}
	
}

sub move_story_to_voting {
	my $S = shift;
	my $sid = shift;
	
	# move the story to the normal queue
	$S->story_post_write('-2', '-2', $sid);

	$S->run_hook('story_leave_editing', $sid) if ($sid);

	# delete registered votes
	my ($rv, $sth) = $S->db_delete({
		DEBUG => 0,
		FROM  => 'storymoderate',
		WHERE => "sid='$sid'"});
	
	$sth->finish;	

	# reset story totals
	($rv, $sth) = $S->db_update({
		DEBUG => 0,
		WHAT =>  'stories',
		SET => 	 'totalvotes=0, score=0',
		WHERE => "sid='$sid'"});
	$sth->finish;
}

sub _post_story {
	my $S = shift;
	my $sid = shift;
	
	my ($votes, $score) = $S->_get_total_votes($sid);
	my $threshold = $S->{UI}->{VARS}->{post_story_threshold};
	my $hide_threshold = $S->{UI}->{VARS}->{hide_story_threshold};
	my $stop_threshold = $S->{UI}->{VARS}->{end_voting_threshold} || -1;

	my $msg;
	my $num;
	my ($dstat, $wstat) = $S->_check_story_status($sid);
	my $sth = $S->_get_story_mods($sid);

	my ($for_votes, $against_votes) = 0;

	# Aha!  Wizardry.  If they want the 'old' scoring then we use $score

	if ( $S->{UI}->{VARS}->{use_alternate_scoring} ) {
		while (my $mod_rec = $sth->fetchrow_hashref) {
			if ($mod_rec->{vote} == 1) {
				$for_votes++;
			} elsif ($mod_rec->{vote} == -1) {
				$against_votes--;
			}
		}
	} else {
		$for_votes = $score;
		$against_votes = $score;
	} 

	$sth->finish;
	
	warn "(_post_story) score is: $score ($for_votes/$against_votes); thresholds are $threshold and $hide_threshold" if $DEBUG;
	warn "(_post_story) dstat: $dstat; wstat: $wstat" if $DEBUG;
	if ($for_votes >= $threshold && $dstat < 0) {    
		# figure out if this story should post to the section or
		# front page
	
		my ($rv1, $sth1) = $S->db_select({
		      WHAT => 'section_only, count(*) as CNT',
		      FROM => 'storymoderate',
		      WHERE => qq|sid = '$sid' AND section_only != 'X'|,
		      GROUP_BY => 'section_only',
		      ORDER_BY => 'CNT DESC'
		    });
	
		my $sec_votes = {};
		while (my ($sec, $num) = $sth1->fetchrow) {
			$sec_votes->{$sec} = $num;
		}
		$sth1->finish();
		
		my $total = $sec_votes->{Y} + $sec_votes->{N};
		my $ratio = $sec_votes->{N} / $total;
		$ratio = sprintf("%.2f", $ratio);
		
		my ($ws, $ds, $where);
		
		$S->{UI}->{VARS}->{front_page_ratio} ||= 0.5;
		
		if( $ratio < $S->{UI}->{VARS}->{front_page_ratio}) {
			$ws = -2;
			$ds = 1;
			$where = "Section";
		} else {
			$ws = 0;
			$ds = 0;
			$where = "front";
		}

		# Post the story
		my $rv = $S->story_post_write($ds, $ws, $sid);
	
		$S->run_hook('story_post', $sid, $where);
		
		if ($rv) {
			$msg = $S->{UI}->{BLOCKS}->{story_post_message};
			$msg =~ s/%%where%%/$where/;
		}

		# Send e-mail to the author
		$S->_send_story_mail($sid, 'posted') if ($S->{UI}->{VARS}->{notify_author} == 1);

	# END: if ($for_votes >= $threshold && $dstat < 0)
	} elsif ($for_votes >= $threshold && $dstat >= 0 && $wstat >= 0) {

		$msg = $S->{UI}->{BLOCKS}->{story_already_post_msg};

	} elsif ($against_votes == $hide_threshold && $dstat < -1) {

		#Story is now hidden
		warn "(_post_story) hiding story $sid" if $DEBUG;
		my $rv = $S->story_post_write('-1', '-1', $sid);

		$S->run_hook('story_hide', $sid);

		$S->_send_story_mail($sid, 'hidden') if ($S->var('notify_author') == 1);
		$msg = $S->{UI}->{BLOCKS}->{story_dumped_message};

	  # This will activate the default (max_votes based) auto-clear
	} elsif ($S->{UI}->{VARS}->{use_auto_post} && !$S->{UI}->{VARS}->{auto_post_use_time} && $votes >= $stop_threshold) {

		$msg .= $S->auto_clear_story($sid);	
      
	  # This will activate the time-based auto clear, if auto_post_use_time is set
	} elsif ($S->{UI}->{VARS}->{use_auto_post} && $S->{UI}->{VARS}->{auto_post_use_time}) {
	    
		# Check for time in auto_clear, instead of above.
		$msg .= $S->auto_clear_story($sid);	
	
	}
	
	return $msg;
}

sub auto_clear_story {
	my $S = shift;
	my $sid = shift;
	
	my $qsid = $S->dbh->quote($sid);
	# Check the current score and posting time. 
	my ($rv, $sth) = $S->db_select({
		WHAT => 'score,  time',
		FROM => 'stories',
		WHERE => qq|sid = $qsid|});
	
	my ($curr_sc, $post_time) = $sth->fetchrow();
	$sth->finish();
	
	# Check the time if necessary 
	if ($S->{UI}->{VARS}->{auto_post_use_time}) {
		my $post_sec = $S->time_absolute_to_seconds($post_time);
		my $diff_minutes = (time() - $post_sec) / 60;
		return unless ($diff_minutes > $S->{UI}->{VARS}->{auto_post_max_minutes});
	}	

	my ($avg, $vote_score, $comment_score) = 0;
	my $msg;
	my $vote_floor = $S->{UI}->{VARS}->{auto_post_floor} || 0;
	my $vote_ceiling = $S->{UI}->{VARS}->{auto_post_ceiling} || $S->{UI}->{VARS}->{post_story_threshold};
	my $section = $S->{UI}->{VARS}->{auto_post_section};
	my $front = $S->{UI}->{VARS}->{auto_post_frontpage};
	
	if ($curr_sc >= $vote_floor) {
		# Get the vote_score
		$vote_score = $S->get_story_vote_score($sid);

		# Then get the weighted comment score
		$comment_score = $S->get_story_comment_score($sid);

		# Then get the average of those
		$avg = ($vote_score + $comment_score) / 2;
		
		# Check for boundary cases
		if ($curr_sc >= $vote_ceiling && $avg < $section) {
			$avg = $section;
		}
	} else {
		$msg = "Overall score less than voting floor ($curr_sc < $vote_floor)";
	}
	
	
	my $ws = -1;
	my $ds = -1;
	
	$ds = 1 if ($avg >= $section);
	$ds = 0 if ($avg >= $front);
	
	# post or drop the story
	$rv = $S->story_post_write($ds, $ws, $sid);
	my $status = ($ds != -1) ? 'posted' : 'hidden';
	my $path = $S->var('rootdir');
	my $url = "http://$S->{SERVER_NAME}$path/story/$sid";
	if ($vote_score && $comment_score) {
		$msg = "Vote score: $vote_score, Comment score: $comment_score, Avg: $avg";
	}
	# temp admin alert
	$S->admin_alert("Story auto-$status: story: $url, $msg") if ($S->var('auto_post_alert'));

	# Send e-mail to the author
	if ($rv) {
		$S->_send_story_mail($sid, $status) if($S->var('notify_author') == 1);
		my $returnmsg = $S->{UI}->{BLOCKS}->{story_autopost_message};
		$returnmsg =~ s/%%status%%/$status/;
		return $returnmsg;
	}
	return '';
}

	
sub story_post_write {
	my $S = shift;
	my ($ds, $ws, $sid) = @_;
	
	my $q_sid = $S->dbh->quote($sid);
	my $time = $S->dbh->quote($S->_current_time());
	my ($rv, $sth) = $S->db_update({
		WHAT => 'stories',
		SET => qq|displaystatus = $ds, writestatus = $ws, time = $time|,
		WHERE => qq|sid = $q_sid|});
	$sth->finish;
	
	return $rv;
}
	
sub get_story_comment_score {
	my $S = shift;
	my $sid = shift;

	my $rating_min = $S->dbh->quote($S->{UI}->{VARS}->{rating_min});
	my $qsid = $S->dbh->quote($sid);
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'points, lastmod',
		FROM => 'comments',
		WHERE => qq|points IS NOT NULL and points >= $rating_min and sid = $qsid and pending = 0|,
		DEBUG => 0});

	my ($sum, $count, $comment_score) = 0;
	while (my ($rating, $number) = $sth->fetchrow()) {
		$count += $number;
		$sum += ($rating * $number);
	}
	
	my $min_ratings = $S->{UI}->{VARS}->{auto_post_min_ratings} || 1;
	$count = $min_ratings if ($count < $min_ratings);
	$comment_score = ($sum / $count);
	return $comment_score;
}

sub get_story_vote_score {
	my $S = shift;
	my $sid = shift;

	# First, fetch all the current votes
	my ($dump, $dontcare, $section, $frontpage);
	my ($rv, $sth) = $S->db_select({
		WHAT     => 'COUNT(vote) AS score, vote, section_only',
		FROM     => 'storymoderate',
		WHERE    => qq|sid = '$sid'|,
		GROUP_BY => 'vote, section_only'
	});
	while (my @votes = $sth->fetchrow_array) {
		if ($votes[1] == -1) {
			$dump = $votes[0];
		} elsif ($votes[1] == 0) {
			$dontcare = $votes[0];
		} elsif ($votes[1] == 1 && $votes[2] == 'Y') {
			$section = $votes[0];
		} elsif ($votes[1] == 1 && $votes[2] == 'N') {
			$frontpage = $votes[0];
		}
	}
	$sth->finish;

	# Get the highest rating value
	my $max_multiplier = $S->{UI}->{VARS}->{rating_max};
	
	# Divide by the three voting options
	my $div = ($max_multiplier / 3);
	
	
	# Now, calculate the story's vote score
	my $t = ($frontpage	* $max_multiplier) + ($section * ($max_multiplier - $div)) + ($dontcare * ($max_multiplier - (2 * $div))) + ($dump);
	my $count = $frontpage + $section + $dontcare + $dump;
	
	my $vote_score = $t / $count;
	
	return $vote_score;
}


=pod

=over 4

=item *
_check_story_validity($sid, $params)

Takes an array ref of the parameters to save_story, and returns 1 if the story
can be posted, 0 otherwise, with an error message.  This checks to see if they have 
permissions to save the story, if the story is too big, if they've chosen a topic, etc.

=back

=cut

sub _check_story_validity {
	my $S = shift;
	my $sid = shift;
	my $params = shift;

	# fucking short circuit the whole thing if it's a fucking goddamned
	# story editor monkey's motherfucking draft bullshit
	return 1 if ($params->{operat} eq 'draft' || $params->{operat} eq 'movq'); ;

	my $currtime = $S->_current_time;

	# Don't let them save if it's an editing story, and 
	# They're over the limit
	if ($params->{edit_in_queue}) {
		my ($disp_mode, $stuff) = $S->_mod_or_show($sid); 
		my $count_in_queue = $S->_count_edit_stories($params->{sid});
		if ($count_in_queue >= $S->{UI}->{VARS}->{max_edit_stories}) {
			my $s = ($S->{UI}->{VARS}->{max_edit_stories} == 1) ? 'y' : 'ies';
			return (0, "Error: You may not have more than $S->{UI}->{VARS}->{max_edit_stories} stor$s in editing at a time.");
		} if ($sid && $disp_mode ne 'edit') {
			return (0, "Error: Story is not currently in editing mode");
		}
	}
	
	# don't let them save it if they don't have a topic, intro, and title and section
	unless ($params->{title}	&& 		# have to have a title...
										# and a valid topic IF they are using
										# topics...
			((	$params->{tid}	&& $params->{tid} ne 'all') || !$S->{UI}->{VARS}->{use_topics}) && 
			($params->{introtext} || $params->{introraw}) && 		# introtext necessary too...
			(($params->{section}) && ($params->{section} ne 'all'))  # and a valid section
			) {

		if ($DEBUG) {
			warn "Not saving: insufficient data.\n";
			foreach my $key (keys %{$params}) {
				warn "\t$key, $params->{$key}\n";
			}
		}

		return (0, "You need to choose a valid topic, title, section, and have text in the introduction to submit a story.");
	}

	# don't let them post to a section they don't have permission to 
	unless( $S->have_section_perm('(norm|autofp|autosec)_post_stories', $params->{'section'}) ) {
		if( $S->have_section_perm('deny_post_stories', $params->{'section'}) ) {
			return (0, "Sorry, but you don't have permission to post stories to section '$params->{'section'}'.");
		} else {
			return (0, "Sorry, that section does not exist.");
		}
	}

	# return 0 if they aren't who they say they are or they are not an editor
	if ($S->{UID} ne $params->{aid} && !$S->have_perm('story_list')) {
	
		# then they are a phoney, return
		warn "Not saving: uid doesn't match aid\n" if ($DEBUG);
		return (0, "Sorry, you don't appear to be a valid editor for this story");
	}

	# Check for sid overwrite
	if( ($S->_check_for_story($sid)) && !$S->have_perm('story_list') ) {
		unless ( ($S->{UID} eq $params->{aid}) ) {	
			# this is an attempt to update an existing story by someone 
			# who doesn't have permission to do so.
			warn "Not saving: sid already exists\n" if ($DEBUG);
			return (0, "Sorry, you don't have permission to update this story");
		}
	}
	
	# Check for posting permissions
	unless( $S->have_perm( 'story_post' ) ) {
		
		# log it in case of script attack
		warn "<< WARNING >> Anonymous Story Posting Denied at $currtime, IP: $S->{REMOTE_IP}   Title: \"$params->{title}\"\n";
		return (0, "Sorry, you don't have permission to post a story here");
	}

	# get word/char maxes for the intro

	# if we're just doing a draft, don't check intro stuff
	return 1 if ($S->cgi->param('operat') eq 'draft');

	# Set it to zero if we have evade_intro_limits perm
	my $max_intro_words = (!$S->have_perm('evade_intro_limits')) ? $S->{UI}->{VARS}->{max_intro_words} : 0;
	my $max_intro_chars = (!$S->have_perm('evade_intro_limits')) ? $S->{UI}->{VARS}->{max_intro_chars} : 0;
	my $min_intro_words = (!$S->have_perm('evade_intro_limits')) ? $S->{UI}->{VARS}->{min_intro_words} : 0;
	my $min_intro_chars = (!$S->have_perm('evade_intro_limits')) ? $S->{UI}->{VARS}->{min_intro_chars} : 0;
	my $max_warn = $S->{UI}->{BLOCKS}->{'max_intro_warning'};
	my $min_warn = $S->{UI}->{BLOCKS}->{'min_intro_warning'};

	# Check number of words in intro
	if( $max_intro_words && ($max_intro_words < $S->count_words($params->{introtext}) )) {
		$max_warn =~ s/__MAXINTRO__/$max_intro_words/g;
		$max_warn =~ s/__UNIT__/words/g;
		return (0, $max_warn); 
	}
	warn $S->count_words($params->{introtext}), " words in intro" if $DEBUG;

	# Check number of chars in intro
	if( $max_intro_chars && ($max_intro_chars < $S->count_chars($params->{introtext}) )) {
                $max_warn =~ s/__MAXINTRO__/$max_intro_chars/g;
                $max_warn =~ s/__UNIT__/characters/g;
                return (0, $max_warn);
	}
	warn $S->count_chars($params->{introtext}), " chars in intro" if $DEBUG;
	
	# And same for min
	if( $min_intro_words && (($min_intro_words > $S->count_words($params->{introtext})) && !$params->{bodytext} )) {
                $min_warn =~ s/__MININTRO__/$min_intro_words/g;
                $min_warn =~ s/__UNIT__/words/g;
                return (0, $min_warn);
        }
        warn $S->count_words($params->{introtext}), " words in intro" if $DEBUG;
	if( $min_intro_chars && (($min_intro_chars > $S->count_chars($params->{introtext})) && !$params->{bodytext} )) {
                $min_warn =~ s/__MININTRO__/$min_intro_chars/g;
                $min_warn =~ s/__UNIT__/characters/g;
                return (0, $min_warn);
        }
        warn $S->count_chars($params->{introtext}), " chars in intro" if $DEBUG;
	return (1, "Success!");
}


sub _count_edit_stories {
	my $S = shift;
	my $sid = shift;
	my $q_aid = $S->dbh->quote($S->{UID});
	my $q_sid = $S->dbh->quote($sid);
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'COUNT(*)',
		FROM => 'stories',
		WHERE => "displaystatus = -3 AND aid = $q_aid AND sid != $q_sid"});
	
	my $count = $sth->fetchrow();
	$sth->finish();
	
	return $count;
}


sub _send_story_mail {
	my $S = shift;
	my $sid = shift;
	my $mode = shift;

	my ($rv, $sth) = $S->db_update({
		WHAT  => 'stories',
		SET   => 'sent_email = 1',
		WHERE => qq|sid = '$sid' AND sent_email = 0|
	});
	$sth->finish;

	# check to make sure the query actually did something. if not, either the
	# sid doesn't exist, or more likely, the email was already sent, and we
	# don't want to send a duplicate
	unless ($rv >= 1) {
		return;
	}

	# get the info needed to send the email
	($rv, $sth) = $S->db_select({
		WHAT => 'aid, title',
		FROM => 'stories',
		WHERE => qq|sid = '$sid'|});
	my $info = $sth->fetchrow_arrayref;
	$sth->finish;
	$info->[1] =~ s/&quot;/"/g;    # unfilter the title
	$info->[1] =~ s/&amp;/&/g;

    my $uid = $info->[0];
    return if $uid == -1;	# anon user doesn't get any e-mail
	my $uname = $S->get_nick_from_uid($uid);
	my $user = $S->user_data($uid);
    my $path = $S->{UI}->{VARS}->{rootdir};
	my $subject;
	my $message;
	my $url = "$S->{UI}->{VARS}->{site_url}$path/story/$sid";
	if ($mode eq "posted") {
		$subject = "Story by $uname has been posted";
		$message = qq|
A story that you submitted titled "$info->[1]" on $S->{UI}->{VARS}->{sitename} has been posted.

If you would like to view the story, it is available at the following URL:

$url

Thanks for using $S->{UI}->{VARS}->{sitename}!

$S->{UI}->{VARS}->{local_email}|;
	} else {
		$subject = "Story by $uname has been hidden";
		$message = qq|
A story that you submitted titled "$info->[1]" on $S->{UI}->{VARS}->{sitename} has been declined by the voters.

It may still be viewed at the following URL, where any posted comments may
give you insight as to why the score dropped:

$url

If you'd like, you may make any needed changes and resubmit your story.

Thanks for using $S->{UI}->{VARS}->{sitename}!

$S->{UI}->{VARS}->{local_email}|;
	}

	$rv = $S->mail($user->{realemail}, $subject, $message);
}#'


sub _check_story_status {
	my $S = shift;
	my $sid = shift;
	$sid = $S->dbh->quote($sid);
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'displaystatus, writestatus',
		ARCHIVE => $S->_check_archivestatus($sid),
		FROM => 'stories',
		WHERE => qq|sid = $sid|});
	
	my $info = $sth->fetchrow_hashref;
	$sth->finish;
	my $dispstat = $info->{displaystatus};
	my $writestat = $info->{writestatus};
	
	return ($dispstat, $writestat);
}


sub _transfer_comments {
	my $S = shift;
	my $sid = shift;
	my $pid = 0;
	my ($uid, $cid, $points, $comment, $subject, $date, $nick);
	$sid = $S->dbh->quote($sid);
	
	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'storymoderate',
		WHERE => qq|sid = $sid|});
	
	my $i = 0;
	while (my $vote = $sth->fetchrow_hashref) {
		if ($vote->{comment}) {
			$cid = $S->_make_cid($sid);
			$uid = $vote->{uid};
			$points = 0;
			$date = $vote->{time};
			$comment = $vote->{comment};
			$subject = $vote->{comment};
			$subject =~ s/<.*?>//g;
			$subject =~ /(.{1,35})/;
			$subject = $1.'...';
			$nick = $S->get_nick($uid);
			$comment = qq|
			<I>$nick voted $vote->{vote} on this story.</I><P>|.$comment;
		
			$comment = $S->{DBH}->quote($comment);
			$subject = $S->{DBH}->quote($subject);
			my ($rv2, $sth2) = $S->db_insert({
				DEBUG => 0,
				INTO => 'comments',
				COLS => 'sid, cid, pid, date, subject, comment, uid, points',
				VALUES => qq|$sid, $cid, $pid, '$date', $subject, $comment, $uid, $points|});
		
			$i++;
		}
	}
	$sth->finish;
	
	$S->_delete_mod_comments($sid);
	return $i;
}


sub _delete_mod_comments {
	my $S = shift;
	my $sid = shift;
	$sid = $S->dbh->quote($sid);
	
	my $rv = $S->db_delete({
		FROM => 'storymoderate',
		WHERE => qq|sid = $sid|});
	
	return 1;
}

sub goddamned_grip_of_controls {
	my $S = shift;
	my $sid = shift;
	# because this stuff *has* to be all done in one place, even though
	# it's a lot of work, the same process creates them, and there isn't
	# a whole lot of point. Not to mention, who knows what else will
	# break. But that's O-fucking-K, isn't it? Worrying about keeping any
	# sort of vague compatibility with the rest of scoop apparently
	# isn't worth worrying about anymore.

	# lifting wholesale from the box that originally did this for the 
	# ajax editor.
	my $story = $S->story_data_arr([$sid]);
	my $aid = $story->[0]->[2];
	my $timecon;
	my $dscon;
	my $seccon;
	my $comcon;
	if($S->have_perm('story_time_update')){
    		$timecon = qq~<input type="checkbox" name="timeupdate" id="timeupdate" value="now" /> <b>Update timestamp</b>~;
    		}
	#if($S->have_perm('story_admin')){
    		my $section = $story->[0]->[10];
		$seccon = $S->section_select($section, $section);
	#	}
	#else {
    	#	$seccon = qq~<input type="hidden" id="section" value="Diary" />~;
    	#	}
	if($S->have_perm('story_displaystatus_select')){
    		my ($seld, $selh, $selfp, $selsp, $seled);
    		my $ds = $story->[0]->[11];
    		# reset $ds if needed
    		if($ds == -4 && $S->have_perm('story_displaystatus_select') && $S->{UID} == $aid){
        		$ds = ($story->[0]->[10] eq 'Diary') ? 1 : 0;
        		}
		elsif ($ds == -5) {
			$ds = ($story->[0]->[10] eq 'Diary') ? 1 : 0;
			}
	    	if($ds == -4) {
        		$seld = " selected=\"selected\"";
        		}
    		elsif($ds == -1){
        		$selh = " selected=\"selected\"";
        		}
		elsif($ds == -5){
			$seled = " selected=\"selected\"";
			}
    		elsif($ds == 0){
        		$selfp = " selected=\"selected\"";
        		}
    		else {
        		$selsp = " selected=\"selected\"";
        		}
    		$dscon = qq~<select name="displaystatus" id="displaystatus" size="1">
    		<option value="0"$selfp >Front Page</option>
    		<option value="1"$selsp >Section Only</option>
    		<option value="-4"$seld >Draft</option>
		<option value="-5"$seled >Edit Queue</option>
    		<option value="-1"$selh >Hide</option>
    		</select>~;
    		}
	if($S->have_perm('story_commentstatus_select')){
    		$comcon = $S->commentstatus_select($story->[0]->[12]) if ($S->have_perm('story_commentstatus_select'));
    		}
	# This, of course, is necessary to keep the flexibility we had with
	# the old way.
	my $ret = {};
	$ret->{timecon} = $timecon;
	$ret->{displaystatus} = $dscon;
	$ret->{commentstatus} = $comcon;
	$ret->{section} = $seccon;
	return $ret;
	}

sub check_for_dsid {
        my $S = shift;
        my $sid = shift;
	my $qsid = $S->dbh->quote($sid);

	#return $S->{DSID}->{$sid} if $S->{DSID}->{$sid};
	if(my $rsid = $S->cache->fetch("dsid_$sid")){
		return $rsid;
		}
        my ($rv, $sth) = $S->db_select({
                WHAT => 'sid, displaystatus',
                FROM => 'stories',
                WHERE => qq|dsid = $qsid|
                });
        my $ns = $sth->fetchrow_hashref();
	my $newsid = $ns->{sid};
	my $disp = $ns->{displaystatus};
        $sth->finish;
	#$S->{DSID}->{$sid} = $newsid if $disp != -4;
	if($disp != -4 && $disp != -5){
		$S->cache->store("dsid_$sid", $newsid);
		}
        # just return newsid. If nothing's there, then the story would 
        # apparently not actually exist.
        return $newsid; # better be safe and return the sid because
				# of older stories
        }

1;
