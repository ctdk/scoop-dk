package Scoop;
use strict;
my $DEBUG = 0;

# the old displaystory function - hopefully gets the legacy editor working
# again

sub old_displaystory {
	my $S = shift;
	my $sid = shift;
	my $story = shift;
	my $mode = $S->{CGI}->param('mode');
	#warn "Sid is $sid";
	my $stories;
	
	$story->{sid} ||= $sid;
	$story->{aid} ||= $S->{UID};
	$story->{nick} ||= $S->get_nick_from_uid($story->{aid});

	# The sid must be bent to our will here
	my $stmp = [];
        #if ($sid eq 'preview'){
                $stmp->[0] = $story->{sid} || $sid;
                $stmp->[2] = $story->{aid} || $S->{UID};
                $stmp->[30] = $story->{nick} || $S->get_nick_from_uid($stmp->[2]);
                $stmp->[1] = $story->{tid};
                $stmp->[10] = $story->{section};
                $stmp->[3] = $story->{title};
                $stmp->[7] = $story->{bodytext};
                $stmp->[6] = $story->{introtext};
                $stmp->[11] = $story->{displaystatus};
                $stmp->[31] = $story->{ftime};
                $stmp->[4] = $story->{dept};
                $stmp->[27] = $story->{hotlisted};
                $stmp->[32] = $story->{comments};
        #        }
	
	#Make sure comment controls are set
	#$S->_set_comment_mode();
	#$S->_set_comment_order();
	#$S->_set_comment_rating_thresh();
	#$S->_set_comment_type();

	#my $rating_choice;
	#$S->_set_comment_rating_choice;
	
	my $rating_choice = $S->get_comment_option('ratingchoice');
		
	unless ($sid eq 'preview' || $S->_does_poll_exist($sid)) {
		$stories = $S->story_data([$sid]);
		if ($stories) {		 
			$story = $stories->[0];
		} else {
			return 0;
		}

	}
	$S->{CURRENT_TOPIC} = $story->{tid};
	$S->{CURRENT_SECTION} = $story->{section};

	# Set the page title
	#$S->{UI}->{BLOCKS}->{subtitle} = $story->{title};
	
	my $page;
	if ( $S->_does_poll_exist($sid) == 1 ) {
		$page .= $S->display_poll($sid);
	} else {
		# warn "getting story summary for $sid\n";
		$page .= $S->old_story_summary($story);
	}

	my ($more, $stats, $section) = $S->story_links($stmp);
	$page =~ s/%%section_link%%/$section/g;

	$page =~ s/%%readmore%%//g;
	
	$page .= qq|%%story_separator%%|;
	
	my $body = $S->{UI}->{BLOCKS}->{story_body};
	my $bodytext = $story->{bodytext};
	$body =~ s/%%bodytext%%/$bodytext/;
	
	if ((exists $S->{UI}->{VARS}->{use_macros} && $S->{UI}->{VARS}->{use_macros})) {
		$body = $S->process_macros($body,'body');
	}

	$page .= $body;

	if ($S->_does_poll_exist($sid) && !$S->have_perm('view_polls')) {
		$page = qq| <b>%%norm_font%%Sorry, you don't have permission to view polls on this site.%%norm_font_end%%</b> |;
	}

	my $story_section = $story->{section} || $S->_get_story_section($sid);
	# check the section permissions
	if ($S->have_section_perm('deny_read_stories', $story_section) && !$S->_does_poll_exist($sid) && ($story->{displaystatus} != -4)) {
		$page = qq| <b>%%norm_font%%Sorry, you don't have permission to read stories posted to this section.%%norm_font_end%%</b> |;
	} elsif ($S->have_section_perm('hide_read_stories', $section) && !$S->_does_poll_exist($sid)) {
		$page = qq| <b>%%norm_font%%Sorry, I can't seem to find that story.%%norm_font_end%%</b> |;
	}

	if ($story->{displaystatus} == '-1') {
		unless ($S->have_perm('moderate') || 
                        ($S->{UID} eq $story->{'aid'} && $S->have_perm('edit_my_stories')) || 
                        $S->have_perm('story_admin')
                       ) { 

			$page = '';
		}
	}
	# This ought to go a long way...
	if ($story->{displaystatus} == -4){
		unless (($story->{aid} == $S->{UID}) || $S->have_perm('story_admin')){
			$page = qq| <b>%%norm_font%%Sorry, I can't seem to find that story.%%norm_font_end%%</b> |;
			}
		}

	return ($story, $page);
}		


sub old_story_summary {
	my $S = shift;
	my $story = shift;
	my $add_readmore = shift || 0;
	my $edit;

	$story->{nick} = $S->{UI}->{VARS}->{anon_user_nick} if $story->{aid} == -1;
	my $linknick = $S->urlify($story->{nick});
	
	my $editlink;
	if ($S->have_perm('edit_user')) {
			$editlink .= qq| [<a href="%%rootdir%%/user/$linknick/edit">Edit User</a>]|;
	}
 	my $urlnick = lc($story->{nick});
	$urlnick =~ s/ /-/g;
	$urlnick = $urlnick . $S->{UI}->{VARS}->{root_domain};
	my $info = qq|<a href="http://$urlnick">$story->{nick}</a>$editlink|;
	my $time = $story->{ftime};
	my $qid = $S->get_qid_from_sid($story->{sid});
	
	if ($S->{UI}->{VARS}->{show_dept} && $story->{dept}) {
		$info .= qq|
 			<br>%%dept_font%%from the $story->{dept} department%%dept_font_end%%|;
	}
	
	my ($topic, $topic_link, $t_link_end, $topic_img, $topic_text);
	
	# are topics enabled, and does the user want to see topic images?
	if ($S->var('use_topics') && 
	    (($S->{UID} == -1 && $S->{PREF_ITEMS}->{show_topic}->{default_value} eq 'on') || 
		($S->{UID} != -1 && (($S->pref('show_topic') eq 'on') )))) {
		$topic = $S->get_topic($story->{tid});
	} else {
		$topic = {};
	}

	# check this, because if it's not set, either topics aren't enabled, or the
	# user doesn't want to see them, or there is no topic for this story
	if ($topic->{tid}) {
		if ($story->{section} eq 'Diary') {
			$topic_link = qq|<A HREF="%%rootdir%%/user/$linknick/diary">|;
		} else {
			$topic_link = qq|<A HREF="%%rootdir%%/?op=search&topic=$topic->{tid}">|;
		}
		
		$t_link_end = '</a>';

		$topic_img = qq|$topic_link<IMG SRC="%%imagedir%%%%topics%%/$topic->{image}" WIDTH="$topic->{width}" HEIGHT="$topic->{height}" ALT="$topic->{alttext}" TITLE="$topic->{alttext}" ALIGN="right" BORDER=0>$t_link_end
		|;
		$topic_text = qq| $topic_link$topic->{alttext}$t_link_end |;
	} else {
		$topic_img = "";
		$topic_text = "";
	}
	
	my $text = qq|$story->{introtext}|;

	if ((exists $S->{UI}->{VARS}->{use_macros} && $S->{UI}->{VARS}->{use_macros})) {
		$text = $S->process_macros($text,'intro');
	}

	my $op = $S->{CGI}->param('op') || 'main';
	# bit of a hack for when user's hotlist something right after posting it,
	# such as a diary. normally, it would take them back to the submitstory
	# page, when in reality they want to be taken to what they just submitted
	$op = 'displaystory' if $op eq 'submitstory';
	my $oplink = "/$op";

	foreach (qw(page section)) {
		my $var = $S->{CGI}->param($_);
		$oplink .= '/';
		$oplink .= $var if $var;
	}

	my $hotlist = '';
#	if ($S->{UID} >= 0 && $story->{displaystatus} >= 0) {
#		my $flag = $S->check_for_hotlist_story($story->{sid});
#		if ($flag) {
	if ( $story->{hotlisted} ) {
		$hotlist = qq|<a href="%%rootdir%%/hotlist/remove/$story->{sid}$oplink">%%hotlist_remove_link%%</a>|;
	} elsif ($S->{UID} > 0) {
		$hotlist = qq|<a href="%%rootdir%%/hotlist/add/$story->{sid}$oplink">%%hotlist_link%%</a>|;
	} 
	
	my $friendlist = '';

	# If a story is new, replace |new| in the story with |new_story_marker|
	my $is_new = (defined($S->story_last_seen($story->{sid})) || $op eq 'displaystory') ? '' : $S->{UI}->{BLOCKS}->{new_story_marker};

	my $section;
	if ($story->{sid} eq 'preview') {
		$section = $S->{SECTION_DATA}->{$story->{section}};	
	} else { 
		$section = $S->{SECTION_DATA}->{ $S->_get_story_section( $story->{sid} )} || undef;
	}
	
	my $tags;
	if ($S->var('use_tags')) {
		$tags = $S->tag_display($story->{sid});
	}
	
	my $page = $S->{UI}->{BLOCKS}->{story_summary};
	#warn "Page is:\n--------------------------------\n$page\n\n";
	$page =~ s/%%info%%/$info/g;
	$page =~ s/%%title%%/$story->{title}/g;
	$page =~ s/%%introtext%%/$text/g;
	$page =~ s/%%hotlist%%/$hotlist/g;
	$page =~ s/%%friendlist%%/$friendlist/g;
	$page =~ s/%%topic_img%%/$topic_img/g;
	$page =~ s/%%topic_text%%/$topic_text/g;
	$page =~ s/%%time%%/$time/g;
	$page =~ s/%%sid%%/$story->{sid}/g;
	$page =~ s/%%section_icon%%/$section->{icon}/g if $section->{icon};
	$page =~ s/%%section_title%%/$section->{title}/g;
	$page =~ s/%%aid%%/$story->{nick}/g;
	$page =~ s/%%section%%/$story->{section}/g;
	$page =~ s/%%tid%%/$story->{tid}/g;
	$page =~ s/%%new%%/$is_new/g;
	$page =~ s/%%tags%%/$tags/g;
	$page =~ s/%%qid%%/$qid/g;
	
	#if( $add_readmore ) {
	if(0){
	    my ($more, $stats, $section_link) = $S->story_links( $story );
	    $page =~ s/%%readmore%%/$more/g;
	    $page =~ s/%%stats%%/$stats/g;
	    $page =~ s/%%section_link%%/$section_link/g;
	    #$page .= qq|<TR><TD>&nbsp;</TD></TR>|;
	}
	return $page;
			
}

1;
