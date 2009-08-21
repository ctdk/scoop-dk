package Scoop;
use strict;

my $DEBUG = 0;

sub frontpage_view {
	my $S = shift;
	my $story_type = shift;
	my $user    = $S->cgi->param('user');
	my $topic   = $S->cgi->param('topic');
	my $params;	# The important stuff args are stored here
	# Added to allow the use of this to create specialty index
	# pages based on factors like posting time, or whatever
	$params->{where} = shift;
	$params->{from} =shift;

	my $page;
        my $uid = $S->{UID};
        if ($S->{UI}->{VARS}->{use_mc_index} && ($page = $S->cache->fetch("index-${story_type}-$uid"))){
                return $page;
                }
	
	my $spage   = $S->cgi->param('page') || 1;
	my $op      = $S->cgi->param('op');
	my $section = $S->cgi->param('section');
	my $disp    = $S->cgi->param('displaystatus');
	my $tag     = $S->cgi->param('tag');

	$params->{topic} = $topic if $topic;
	$params->{user} = $user if $user;
	$params->{page} = $spage if $spage;


	# ugh. hack in the old behavior for Diaries for now, I guess
        my $story_params = {-type => $story_type};
        $story_params->{-topic} = $topic if ($topic ne '');
        $story_params->{-user}  = $user if ($user ne '');
        $story_params->{-page}  = $spage if $spage;
        $story_params->{-where} = $params->{where} if $params->{where};
        $story_params->{-from} = $params->{from} if $params->{from};
	
	if ( $story_type eq 'main' ) {
		$params->{displaystatus} = $disp || '0';
	} elsif ( $story_type eq 'section' ) {
		$params->{displaystatus} = $disp || [0,1];
		$params->{section} = $section;
	} elsif ($story_type eq 'tag' ) {
		$params->{displaystatus} = $disp || [0,1];
		$params->{tag} = $tag;
	}
	
	# if they don't have permission to view this section, let them know
	if( $section && $section ne ''		&&
		$section ne '__all__'			&&
		!$S->have_section_perm( 'norm_read_stories', $section ) ) {
		# safinate this
		my $safesec = $S->filter_param($section);
		if( $S->have_section_perm( 'deny_read_stories', $section ) ) {
			return qq|<b>%%norm_font%%Sorry, you don't have permission to read stories posted to section '$safesec'.%%norm_font_end%%</b>|;
		} else {
			return qq|<b>%%norm_font%%Sorry, I can't seem to find section '$safesec'.%%norm_font_end%%</b>|;
		}

	}

	if ($user) {
		my $uid = $S->get_uid_from_nick($user);
		return qq|<b>%%norm_font%%Sorry, I can't seem to find that user.%%norm_font_end%%</b>| unless ($uid);
	}

	my $sids;
	my $stories;
	#if($section eq 'Diary'){
	#$stories = $S->getstories($story_params);
	#	}
	#else {
	$sids = $S->get_story_ids($params);
	$stories = $S->story_data_arr($sids);
	#	}
	my $c = 0;
	foreach my $story (@{$stories}) {
		$page .= $S->story_summary($story);
		my ($more, $stats, $section) = $S->story_links($story);
		$page =~ s/%%readmore%%/$more/g;
		$page =~ s/%%stats%%/$stats/g;
		$page =~ s/%%section_link%%/$section/g;
		$c++;
                # Normally, this would be in a box, but since it's in the
                # middle of the fp, this is as good of a place to put it as
                # any.
                if ($c == 1 && ($S->{UI}->{VARS}->{midfp_ad})){
                        unless (($S->have_perm('ad_opt_out') && ($S->pref('showad') eq 'off')) || ($S->apache->headers_in->{'User-Agent'} =~ /AppleWebKit/ && $S->apache->headers_in->{'User-Agent'} !~ /Version/)){
                                $page .= $S->{UI}->{BLOCKS}->{banner_midfp};
                                }
                        }
	}

	# now make the links for next/previous pages, and put them on
	my ($np, $pp) = ($spage + 1, $spage - 1);
	my $pre_link  = ($op eq 'section' || $op eq 'crawl') ? "$op/$section" : "$op";

	if ($section eq 'Diary' && $user) {
		$pre_link = "user/$user/diary";
	} elsif ($op eq 'tag') {
		$pre_link = "tag/$tag";
	}
	my $change_page = $S->{UI}->{BLOCKS}->{next_previous_links};
	my ($prev_page, $next_page);
	if ($pp >= 1) {
		$prev_page = $S->{UI}->{BLOCKS}->{prev_page_link};
		$prev_page =~ s/%%LINK%%/%%rootdir%%\/$pre_link\/$pp/g;
	}
	if (@{$stories} && @{$stories} == $S->pref('maxstories')) {
		$next_page = $S->{UI}->{BLOCKS}->{next_page_link};
		$next_page =~ s/%%LINK%%/%%rootdir%%\/$pre_link\/$np/g;
	}
	$change_page =~ s/%%PREVIOUS_LINK%%/$prev_page/g;
	$change_page =~ s/%%NEXT_LINK%%/$next_page/g;

	#$page  = $change_page . $page if $pp >= 1;
	$page .= $change_page;

	$S->cache->store("index-${story_type}-$uid", $page, "+5m") if ($S->{UI}->{VARS}->{use_mc_index} && !$S->have_perm('story_admin'));
	return $page;
}

sub story_links {
	my $S = shift;
	my $story = shift;
	
	my $edit = '';
	my $modo = $S->moduloze($story->[26]);
	if ($S->have_perm('story_list') || ($S->have_perm('edit_my_stories') && $story->[2] == $S->{UID})) {
		$edit = qq|[<a href="%%site_url%%%%rootdir%%/storyonly/$story->[0]/$modo/$story->[26]?mode=edit">edit</a>]|;
	} 

	# This is so that if there is no body to the article, it just shows
	# "Comments >>" (or whatever no_body_txt is), instead of Read More
	my $text = ($story->[7] ne '')? '%%readmore_txt%%' : '%%no_body_txt%%';
	# just in case you don't have no_body_txt set
	$text = ($text eq '') ? 'Comments >>' : $text;	

	my $kraft = $S->urlcraft($story->[26]);
	my $more .= qq|<a href="%%site_url%%%%rootdir%%/story/$kraft">$text</a> | unless
		(($S->have_section_perm(hide_read_comments => $story->[10])) &&
		($S->have_section_perm(hide_post_comments => $story->[10])) &&
		($story->{bodytext} eq ''));
			
	# either count words or bytes in the story
	# if you count bytes, it costs you an extra SELECT statement
	# to the database
	# if you count words, it costs you an extra call to 
	# split

	my $bits;
	my @tmp_array;
	#if( $S->{UI}->{VARS}->{story_count_words} == 1 )
	#{
		# used to split to @_, but that gave a 'deprecated' message on startup, thus tmp_array
	#	@tmp_array = split /\s/, $story->[7].$story->[6];
		#$bits = @tmp_array;
	#	$bits .= ($bits == 1) ? " word" : " words";
	#} else {
	#	$bits = $S->count_bits($story->[0]);
	#}

	my @readmore = ();
	my $comment_word = $S->{UI}->{BLOCKS}->{comment_word} || 'comment';
	my $comment_plural = $S->{UI}->{BLOCKS}->{comment_plural} || 's';
	# FIXME: alternate comment counting stuff
	#$story->{comments} ||= $story->{commentcount};
	# shouldn't need this alternate anymore, I hope...
	push @readmore, sprintf( "$S->{UI}->{BLOCKS}->{comment_num_format_start}%d$S->{UI}->{BLOCKS}->{comment_num_format_end} %s%s",
				 $story->[32],
				 $comment_word,
				 $story->[32] != 1 ? $comment_plural : ''
				 ) if( $story->[32] && $S->have_section_perm('norm_read_comments',$story->[10]) );

	my $show = $S->{UI}->{VARS}->{show_new_comments};
	if ($show eq "all" && !$S->have_section_perm('hide_read_comments',$story->[10]) ) {
		my $new_comment_format_start = $S->{UI}->{BLOCKS}->{new_comment_format_start} || '<b>';
		my $new_comment_format_end = $S->{UI}->{BLOCKS}->{new_comment_format_end} || '</b>';
		my $num_new = $S->new_comments_since_last_seen($story->[0]);
		push @readmore, "$new_comment_format_start$num_new$new_comment_format_end new" if $num_new;
	}

	#push @readmore, "$bits in story" if ($bits and $story->{bodytext});
	
	my $section = $S->get_section($story->[10]);
	my $sec_url = qq|%%site_url%%%%rootdir%%/section/$story->[10]|;
	
	my $section_link = qq(<A CLASS="section_link" href="$sec_url">$section->{title}</a>);
		
	my $stats = sprintf( '(%s)', join ', ', @readmore );

	# get rid of empty parenthasis if 0 comments and 0 bytes in body
	if( $stats eq '()' ) {
		$stats = '';
	}

	$more .= qq| $edit |;
	
	return ($more, $stats, $section_link);
}


sub focus_view {
	my $S = shift;

	my $mode = $S->{CGI}->param('mode');
	my $sid = $S->{CGI}->param('sid');
	my $id = $S->cgi->param('id');
	my $caller_op = $S->cgi->param('caller_op');
	# if $sid doesn't actually exist, redirect back to the fp.
	if(!$sid){
 	    my $redir = $S->{UI}->{VARS}->{site_url} . "/";
	    $S->{APACHE}->headers_out->{'Location'} = $redir;
	    $S->{HEADERS_ONLY}=1;
	    }
	
	my $comments;
	
	#$S->{UI}->{BLOCKS}->{STORY} = qq|
	#	<TABLE CELLPADDING=0 CELLSPACING=0 BORDER=0 width="100%">|;
	#$S->{UI}->{BLOCKS}->{COMMENTS} = qq|
	#	<TABLE CELLPADDING=0 CELLSPACING=0 BORDER=0 width="100%">|;

	# Filter this through get_sids for perms
	my $sids = ($id) ? $S->get_story_ids({'id' => $id}) : $S->get_story_ids({'sid' => $sid});
	#$sid = $sids->[0];
	$id = $sids->[0];
	# hrmph. We need to use get_sids too. I still think this whole process
	# will lead to a general faster fetching.
	$sids = ($id) ? $S->get_sids({'id' => $id}) : $S->get_sids({'sid' => $sid});
	$sid = $sids->[0];
	# what do we think sid is?

	# if $sid doesn't exist, check and see if maybe we're trying to get
	# the draft sid of it and redirect if necessary
	# This ought to work, anyway
	if(!$sid){
		my $nsid = $S->check_for_dsid($S->cgi->param('sid'));
		my $cop = $S->cgi->param('caller_op');
		if($nsid) {
			# Redirect the fuck outta here to the new sid.
			my $redir = $S->{UI}->{VARS}->{site_url} . "/$cop/$nsid";
            		$S->{APACHE}->headers_out->{'Location'} = $redir;
            		$S->{HEADERS_ONLY}=1;
			}
		# If $nsid is false, then apparently the story doesn't exist at
		# all, and we just let the normal processes go their way
		}

	my ($story_data, $story) = $S->displaystory($id || $sid);

	my $checkstory = $S->_check_for_story($sid);

	my $commentstatus = $S->_check_commentstatus($sid);
	
	# Run a hook here to do any processing we need to do on a story
	# before we display it.
	$S->run_hook('story_view', $sid, $story_data);

	unless ($checkstory && $story_data && $story) {
		my ($j, $k, $l);
		$j = 1 if $checkstory;
		$k = 1 if $story_data;
		$l = 1 if $story;
		$S->{UI}->{BLOCKS}->{STORY} .= qq|
			<table cellpadding="0" cellspacing="0" border="0" width="100%">
				<tr><td>%%norm_font%%<b>Sorry. I can\'t seem to find that story. j $j k $k l $l</b>%%norm_font_end%%</td></tr>
			</table>|;
			
		return;
	}
	
	
	$S->{UI}->{BLOCKS}->{STORY} .= $story;
	if ($story_data->[11] == -2) {
		$mode = 'moderate';
	}	
	
	if ($story_data->[11] <= -2 && $story_data->[11] > -4) { 
		if (!$S->have_perm('moderate')) {
			$S->{UI}->{BLOCKS}->{STORY} = qq|
			<table width="100%" border="0" cellpadding="0" cellspacing="0">
			<tr bgcolor="%%title_bgcolor%%">
				<td>%%title_font%%Permission Denied.%%title_font_end%%</td>
			</tr>
			<tr><tr>%%norm_font%%Sorry, but you can only moderate stories if you have a valid user account. 
			Luckily for you, making one is easy! Just <a HREF="%%rootdir%%/newuser">go here</a> to get started.
			%%norm_font_end%%</td></tr>
			</table>|;
			return;
		}
		
		my $message = $S->_story_mod_write($sid);
		if ($message) {
			$S->{UI}->{BLOCKS}->{STORY} .= qq|<table width="100%" border=0 cellpadding=0 cellspacing=0><tr><td>%%norm_font%%$message %%norm_font_end%%</td></tr></table>|;
			$S->{UI}->{BLOCKS}->{STORY} .= '<P>';
		}
		my ($which, $mod_stuff) = $S->story_mod_display($sid);
		my $author_control = $S->author_control_display($story_data);
		warn "Author block is:\n$author_control\n" if $DEBUG;

		$S->{UI}->{BLOCKS}->{STORY} .= $author_control;
		
		if ($which eq 'content') {
			$S->{UI}->{BLOCKS}->{STORY} .= $mod_stuff if ($story_data->[2] ne $S->{UID});
		} else {
			$S->{UI}->{BLOCKS}->{BOXES} .= $mod_stuff;
		}
	}
	
	$comments = $S->display_comments($sid, '0') unless $commentstatus == -1 || $caller_op eq 'storyonly'; # || ($S->pref('commentDisplayMode') eq 'hide';
	# grumbles grumble but they don't fall down.
	if($comments || ($caller_op ne 'storyonly' && $commentstatus != -1)){
		#my $bar = $S->run_box('comment_controls',1);
		#$comments .= $bar;
		$comments = $S->{UI}->{BLOCKS}->{comment_div_start} . $comments . $S->{UI}->{BLOCKS}->{comment_div_end};
		}
	$S->update_seen_if_needed($sid) unless $caller_op eq 'storyonly' || $S->pref('commentDisplayMode') eq 'hide';# unless ($S->{UI}->{VARS}->{use_static_pages});
	
	$S->{UI}->{BLOCKS}->{STORY} .= $S->story_nav($sid);
	#$S->{UI}->{BLOCKS}->{STORY} .= '<TR><TD>&nbsp;</TD></TR>';

	$S->{UI}->{BLOCKS}->{COMMENTS} .= $S->comment_controls($sid, 'top');
	$S->{UI}->{BLOCKS}->{COMMENTS} .= qq|$comments|;

	if ($comments) {
		$S->{UI}->{BLOCKS}->{COMMENTS} .= $S->comment_controls($sid, 'top');
	}
	
	#$S->{UI}->{BLOCKS}->{STORY} .= '</TABLE>';
	#$S->{UI}->{BLOCKS}->{COMMENTS} .= '</TABLE>';

	$S->{UI}->{BLOCKS}->{subtitle} .= $story_data->[3] || $S->{UI}->{BLOCKS}->{slogan};
	$S->{UI}->{BLOCKS}->{subtitle} =~ s/</&lt;/g;
	$S->{UI}->{BLOCKS}->{subtitle} =~ s/>/&gt;/g;

	return;
}

# DEPRECATED
# SHOULD PROBABLY REMOVE.
sub olderlist {
	my $S = shift;
	
	my $page = $S->{CGI}->param('page') || 1;
	
	my $next_page = $page + 1;
	my $last_page = $page - 1;
	my $num = $S->{UI}->{VARS}->{storylist};
	my $limit;
	my $get_num = $num + 1;
	my $displayed = $S->pref('maxstories') + $S->pref('maxtitles');
	my $offset = ($num * ($page - 1)) + $displayed;
	my $date_format;
	my $op = $S->{CGI}->param('op');
	
	if(lc($S->{CONFIG}->{DBType}) eq "mysql") {
		$date_format = 'DATE_FORMAT(time, "%a %b %D, %Y at %r")';
	} else {
		$date_format = "TO_CHAR(time, 'Dy Mon DD, YYYY at HH12:MI:SS PM')";
	}
	$limit = "$offset, $get_num";
	
	my ($rv, $sth) = $S->db_select({
		WHAT => qq|sid, aid, users.nickname AS nick, tid, $date_format AS ftime, title|,
		FROM => 'stories LEFT JOIN users ON stories.aid = users.uid',
		WHERE => 'displaystatus >= 0',
		ORDER_BY => 'time DESC',
		LIMIT => $get_num,
		OFFSET => $offset
	});
	
	my $list;
	my $i = $offset + 1;
	my $stop = $offset + $num;
	
	while ((my $story = $sth->fetchrow_hashref) && ($i <= $stop)) {
		warn "In olderlist, getting count for $story->{sid}\n" if $DEBUG;
		$story->{commentcount} = $S->_commentcount($story->{sid});
		$story->{nick} = $S->{UI}->{VARS}->{anon_user_nick} if $story->{aid} == -1;
		$list .= qq|
		<p>
		<b>$i) <a href="%%rootdir%%/story/$story->{sid}">$story->{title}</a></b> by $story->{nick}, $story->{commentcount} comments</p>
		posted on $story->{ftime}|;
		$i++;
	}
	$sth->finish;
	
	my $content = qq|
		<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0 WIDTH=100%>
		<TR>
		<TD COLSPAN=2 BGCOLOR="%%title_bgcolor%%">%%title_font%%<B>Older Stories</B>%%title_font_end%%</TD>
		</TR>
		<TR><TD COLSPAN=2>&nbsp;</TD></TR>
		<TR><TD COLSPAN=2>%%norm_font%%
		$list
		%%norm_font_end%%</TD></TR>|;
	
	$content .= qq|
		<TR><TD COLSPAN=2>&nbsp;</TD></TR>
		<TR>
			<TD>%%norm_font%%<B>|;
	if ($last_page >= 1) {
		$content .= qq|&lt; <a href="%%rootdir%%/?op=$op;page=$last_page">Last $num</a>|;
	} else {
		$content .= '&nbsp;';
	}
	$content .= qq|</B>%%norm_font_end%%</TD>
		<TD ALIGN="right" COLSPAN=2>%%norm_font%%<B>|;
	
	if ($rv >= ($num + 1)) {
		$content .= qq|
		<a href="%%rootdir%%/?op=$op;page=$next_page">Next $num</a> &gt;%%norm_font_end%%|;
	} else {
		$content .= '&nbsp;';
	}
	
	$content .= qq|</B>%%norm_font_end%%</TD>
	</TR>
	</TABLE>|;
	
	$S->{UI}->{BLOCKS}->{CONTENT} = $content;
	return;
}
		
	
1;
