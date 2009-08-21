package Scoop;
use strict;
my $DEBUG = 0;

=head1 Elements.pm

Story functions. Needs documentation...

=cut

sub displaystory {
	my $S = shift;
	my $sid = shift;
	my $story = shift;
	my $mode = $S->{CGI}->param('mode');
	#warn "Sid is $sid";
	my $stories;
	my $id;
	
	#$story->{sid} ||= $sid;
	#$story->{aid} ||= $S->{UID};
	#$story->{nick} ||= $S->get_nick_from_uid($story->{aid});

	# The sid must be bent to our will here
	if ($sid eq 'preview'){
		my $stmp = [];
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
		$story = undef;
		$story = $stmp;
		}
	
	#Make sure comment controls are set
	#$S->_set_comment_mode();
	#$S->_set_comment_order();
	#$S->_set_comment_rating_thresh();
	#$S->_set_comment_type();

	#my $rating_choice;
	#$S->_set_comment_rating_choice;
	
	my $rating_choice = $S->get_comment_option('ratingchoice');
		
	unless ($sid eq 'preview' || $S->_does_poll_exist($sid)) {
		$stories = $S->story_data_arr([$sid]);
		if ($stories) {		 
			$story = $stories->[0];
			# make sure we have both sid and id
			$sid = $story->[0];
			$id = $story->[26];
		} else {
			return 0;
		}

	}
	$S->{CURRENT_TOPIC} = $story->[1];
	$S->{CURRENT_SECTION} = $story->[10];

	# Set the page title
	#$S->{UI}->{BLOCKS}->{subtitle} = $story->[3];
	
	my $page;
	if ( $S->_does_poll_exist($sid) == 1 ) {
		$page .= $S->display_poll($sid);
	} else {
		# warn "getting story summary for $sid\n";
		$page .= $S->story_summary($story);
	}

	my ($more, $stats, $section) = $S->story_links($story);
	$page =~ s/%%section_link%%/$section/g;

	$page =~ s/%%readmore%%//g;
	
	$page .= qq|%%story_separator%%|;
	
	my $body = $S->{UI}->{BLOCKS}->{story_body};
	my $bodytext = $story->[7];
	$body =~ s/%%bodytext%%/$bodytext/;
	
	if ((exists $S->{UI}->{VARS}->{use_macros} && $S->{UI}->{VARS}->{use_macros})) {
		$body = $S->process_macros($body,'body');
	}

	$page .= $body;

	if ($S->_does_poll_exist($sid) && !$S->have_perm('view_polls')) {
		$page = qq| <b>%%norm_font%%Sorry, you don't have permission to view polls on this site.%%norm_font_end%%</b> |;
	}

	my $story_section = $story->[10] || $S->_get_story_section($sid);
	# check the section permissions
	if ($S->have_section_perm('deny_read_stories', $story_section) && !$S->_does_poll_exist($sid) && ($story->[11] != -4)) {
		$page = qq| <b>%%norm_font%%Sorry, you don't have permission to read stories posted to this section.%%norm_font_end%%</b> |;
	} elsif ($S->have_section_perm('hide_read_stories', $section) && !$S->_does_poll_exist($sid)) {
		$page = qq| <b>%%norm_font%%Sorry, I can't seem to find that story A.%%norm_font_end%%</b> |;
	}

	if ($story->[11] == '-1') {
		unless ($S->have_perm('moderate') || 
                        ($S->{UID} eq $story->[2] && $S->have_perm('edit_my_stories')) || 
                        $S->have_perm('story_admin')
                       ) { 

			$page = '';
		}
	}
	# This ought to go a long way...
	if ($story->[11] == -4){
		unless (($story->[2] == $S->{UID}) || $S->have_perm('story_admin')){
			$page = qq| <b>%%norm_font%%Sorry, I can't seem to find that story B.%%norm_font_end%%</b> |;
			}
		}

	return ($story, $page);
}		


sub story_summary {
	my $S = shift;
	my $story = shift;
	my $add_readmore = shift || 0;
	my $edit;

	$story->[30] = $S->{UI}->{VARS}->{anon_user_nick} if $story->[2] == -1;
	my $linknick = $S->urlify($story->[30]);
	
	my $editlink;
	if ($S->have_perm('edit_user')) {
			$editlink .= qq| [<a href="%%rootdir%%/user/$linknick/edit">Edit User</a>]|;
	}
 	my $urlnick = lc($story->[30]);
	$urlnick =~ s/ /-/g;
	$urlnick = $urlnick . $S->{UI}->{VARS}->{root_domain};
	my $info = qq|<a href="http://$urlnick">$story->[30]</a>$editlink|;
	my $time = $story->[31];
	my $qid = $S->get_qid_from_sid($story->[0]);
	
	if ($S->{UI}->{VARS}->{show_dept} && $story->[4]) {
		$info .= qq|
 			<br>%%dept_font%%from the $story->[4] department%%dept_font_end%%|;
	}
	
	my ($topic, $topic_link, $t_link_end, $topic_img, $topic_text);
	
	# are topics enabled, and does the user want to see topic images?
	if ($S->var('use_topics') && 
	    (($S->{UID} == -1 && $S->{PREF_ITEMS}->{show_topic}->{default_value} eq 'on') || 
		($S->{UID} != -1 && (($S->pref('show_topic') eq 'on') )))) {
		$topic = $S->get_topic($story->[1]);
	} else {
		$topic = {};
	}

	# check this, because if it's not set, either topics aren't enabled, or the
	# user doesn't want to see them, or there is no topic for this story
	if ($topic->{tid}) {
		if ($story->[10] eq 'Diary') {
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
	
	my $text = qq|$story->[6]|;

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
	if ( $story->[27] ) {
		$hotlist = qq|<a href="%%rootdir%%/hotlist/remove/$story->[0]$oplink">%%hotlist_remove_link%%</a>|;
	} elsif ($S->{UID} > 0) {
		$hotlist = qq|<a href="%%rootdir%%/hotlist/add/$story->[0]$oplink">%%hotlist_link%%</a>|;
	} 
	
	my $friendlist = '';

	# If a story is new, replace |new| in the story with |new_story_marker|
	my $is_new = (defined($S->story_last_seen($story->[0])) || $op eq 'displaystory') ? '' : $S->{UI}->{BLOCKS}->{new_story_marker};

	my $section;
	if ($story->[0] eq 'preview') {
		$section = $S->{SECTION_DATA}->{$story->[10]};	
	} else { 
		# Why the fuck was this calling _get_story_section
		# unnecessarily???
		$section =  $S->{SECTION_DATA}->{$story->[10]} || $S->{SECTION_DATA}->{ $S->_get_story_section( $story->[0])} || undef;
	}
	
	my $tags;
	if ($S->var('use_tags')) {
		$tags = $S->tag_display($story->[0]);
	}
	
	my $page = $S->{UI}->{BLOCKS}->{story_summary};
	#warn "Page is:\n--------------------------------\n$page\n\n";
	$page =~ s/%%info%%/$info/g;
	$page =~ s/%%title%%/$story->[3]/g;
	$page =~ s/%%introtext%%/$text/g;
	$page =~ s/%%hotlist%%/$hotlist/g;
	$page =~ s/%%friendlist%%/$friendlist/g;
	$page =~ s/%%topic_img%%/$topic_img/g;
	$page =~ s/%%topic_text%%/$topic_text/g;
	$page =~ s/%%time%%/$time/g;
	$page =~ s/%%sid%%/$story->[0]/g;
	$page =~ s/%%section_icon%%/$section->{icon}/g if $section->{icon};
	$page =~ s/%%section_title%%/$section->{title}/g;
	$page =~ s/%%aid%%/$story->[30]/g;
	$page =~ s/%%section%%/$story->[10]/g;
	$page =~ s/%%tid%%/$story->[1]/g;
	$page =~ s/%%new%%/$is_new/g;
	$page =~ s/%%tags%%/$tags/g;
	$page =~ s/%%qid%%/$qid/g;
	$page =~ s/%%id%%/$story->[26]/g;
	
	if( $add_readmore ) {
	    my ($more, $stats, $section_link) = $S->story_links( $story );
	    $page =~ s/%%readmore%%/$more/g;
	    $page =~ s/%%stats%%/$stats/g;
	    $page =~ s/%%section_link%%/$section_link/g;
	    #$page .= qq|<TR><TD>&nbsp;</TD></TR>|;
	}
	return $page;
			
}

=over 4

=item $S->getstories($args_hashref)

This is deprecated. It is also rather nutty. Use $S->story_data() instead.

=back

=cut

sub getstories {
	my $S = shift;
	my $args = shift;

	my ($rv, $sth);
	my $return_stories = [];
	warn "(getstories) starting..." if $DEBUG;
	my $type = $args->{'-type'};
	my $topic = $args->{'-topic'};
        my $user = $args->{'-user'};
	my $maxstories = $args->{'-maxstories'} || $S->pref('maxstories');

	my $section = $args->{'-section'};
	$section = $S->{CGI}->param('section') unless ($section);
	
	my $date_format = $S->date_format('time');
	my $wmd_format = $S->date_format('time', 'WMD');

	# get some sql to make sure they can't get stories that are in sections
	# they aren't allowed to view
	my $excl_sect_sql = $S->get_disallowed_sect_sql('norm_read_stories');
	my $excl_sect_sql_wAND = ' AND ' . $excl_sect_sql;
	$excl_sect_sql_wAND = '' if( $excl_sect_sql_wAND eq ' AND ' );

	# Now get SQL to insure we retrieve inherited content
	my $inherited_sect_sql= ($S->{UI}{VARS}->{enable_subsections})?$S->get_inheritable_sect_sql($section):'';

	my $archive = 0;
	$archive = $S->_check_archivestatus($args->{-sid}) if exists($args->{'-sid'});

        # need this for joining stories to users. if we're looking in the archive,
	# the users table is in a different database, so we have to include the
	# db
	# name to access it
        my $db_name;
	$db_name = $S->{CONFIG}->{db_name} . ".users" if (lc($S->{CONFIG}->{DBType}) eq "mysql");
	$db_name = "users" if (!(lc($S->{CONFIG}->{DBType}) eq "mysql"));

	if ($type eq 'summaries') {
		my $ds = exists($args->{-dispstatus}) ? $args->{-dispstatus} : 0;
		my $page = $args->{-page};

		my @where;
		push(@where, "displaystatus = $ds")   if defined($ds);
		push(@where, "sid = '$args->{-sid}'") if exists($args->{'-sid'});
		push(@where, $excl_sect_sql) if ($excl_sect_sql ne '');
		push(@where, $args->{-where}) if ($args->{-where});

		my $maxstories = $S->pref('maxstories');
		my $offset = (($page * $maxstories) - $maxstories) if $page;
		my $from = qq|stories s LEFT JOIN $db_name u ON s.aid = u.uid|;
		
		$from .= " $args->{-from}" if ($args->{-from});
		
		($rv, $sth) = $S->db_select({
			DEBUG => $DEBUG,
			ARCHIVE => $archive,
			WHAT  => qq{s.sid, s.tid, s.aid, u.nickname AS nick, s.title, s.dept, $date_format AS ftime, s.introtext, s.bodytext, s.section, s.displaystatus},
			FROM  => $from,
			WHERE => join(" AND ", @where),
			ORDER_BY => q{time desc},
			LIMIT => $maxstories,
			OFFSET => $offset
		});
		my $count = $maxstories;
		
		while (my $story = $sth->fetchrow_hashref) {
			#warn "In Elements, getting commentcount for $story->{sid}\n";
			$story->{commentcount} = $S->_commentcount($story->{sid});	
			$story->{archived} = 0;
			push (@{$return_stories}, $story);
			$count --;
		}
		if ($S->{HAVE_ARCHIVE} && ($count > 0) && ( !exists($args->{'-sid'}))) {
			$sth->finish();
			($rv, $sth) = $S->db_select({
				DEBUG => $DEBUG,
				ARCHIVE => 0,
				WHAT => qq|count(sid)|,
				FROM  => q{stories},
				WHERE => join(" AND ", @where),
				ORDER_BY => q{time desc}
			});
			
			my $maxoffset = $sth->fetchrow;
			$sth->finish();
			my $newoffset = $offset - $maxoffset + ($maxstories - $count);
			($rv, $sth) = $S->db_select({
				ARCHIVE => 1,
				DEBUG => $DEBUG,
				WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
				FROM => $from,
				WHERE => join(" AND ", @where),
				ORDER_BY => 'time desc',
				LIMIT => $count,
				OFFSET => $newoffset
			});
			
			while (my $story = $sth->fetchrow_hashref) {
				#warn "In Elements, getting commentcount for $story->{sid}\n";
				$story->{commentcount} = $S->_commentcount($story->{sid});	
				$story->{archived} = 1;
				push (@{$return_stories}, $story);
			}
		}
		$sth->finish;
	
		return $return_stories;

	} elsif ($type eq 'fullstory') {
		my $displaystatus = ' AND displaystatus >= 0';
		if ($S->have_perm('story_list') || $args->{'-perm_override'}) {
			$displaystatus = '';
		} elsif ($S->have_perm('moderate')) {
			$displaystatus = ' AND (displaystatus >= 0 OR displaystatus = -2)';
		}
		($rv, $sth) = $S->db_select({
			ARCHIVE => $archive,
			WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus, time|,
			FROM => "stories s LEFT JOIN $db_name u ON s.aid = u.uid",
			WHERE => qq|sid = '$args->{-sid}' $displaystatus $excl_sect_sql_wAND|,
			DEBUG => $DEBUG
			});
	} elsif ($type eq 'titlesonly') {
		my ($where, $limit);
		
		if ($args->{'-sid'}) {
			my $sid = $S->dbh->quote($args->{'-sid'});
			$where = qq|sid = $sid AND |;
			$limit = '';
		}
		if (defined($args->{'-section'})) {
			my $operator = '=';
			if ($args->{'-section'} =~ /^\!(.*)$/) {
				$operator = '!=';
				$args->{'-section'} = $1;
			}
			$where .= qq|section $operator \'$args->{'-section'}\' AND |;
		}
		if (defined($args->{'-topic'})) {
			my $operator = '=';
			if ($args->{'-topic'} =~ /^\!(.*)$/) {
				$operator = '!=';
				$args->{'-topic'} = $1;
			}
			$where .= qq|tid $operator \'$args->{'-topic'}\' AND |;
		}
		
		if (defined($args->{'-displaystatus'})) {
			$where .= qq|displaystatus = $args->{'-displaystatus'} |;
		} else {
			$where .= 'displaystatus >= 0 ';
		}

		$where .= $excl_sect_sql_wAND;

		$where .= " AND $args->{-where}" if $args->{-where};
		
		($rv, $sth) = $S->db_select({
			DEBUG => $DEBUG,
			ARCHIVE => $archive,
			WHAT  => qq{sid, title, $wmd_format AS ftime},
			FROM  => q{stories},
			WHERE => $where,
			LIMIT => $S->pref('maxtitles'),
			OFFSET => $S->pref('maxstories'),
			ORDER_BY => q{time desc}
		});
	} elsif ($type eq 'titlesonly-section') {
		($rv, $sth) = $S->db_select({
			ARCHIVE => $archive,
			DEBUG => $DEBUG,
			WHAT  => qq{sid, title, $wmd_format AS ftime},
			FROM  => q{stories},
			WHERE => q{displaystatus >= 0 AND section = 'section' $excl_sect_sql_wAND},
			LIMIT => $S->pref('maxtitles'),
			OFFSET => $S->pref('maxstories'),
			ORDER_BY => q{time desc}
		});
	} elsif ($type eq 'section') {
		my $page = $args->{-page};

		# first build up the WHERE part of the SQL query

		my $sec_where;
		if( $section ne '__all__') {
		        if(!$user){
			    $sec_where = qq|AND (section = '$section' |;

			    if( $inherited_sect_sql ) {
				$sec_where.='OR '.$inherited_sect_sql;
			    }
			
			$sec_where .= ") ";
			}
		}
		else {
			my $ex_sec = $S->excluded_from_all_stories();
			$sec_where = qq|$ex_sec|;
		}

		$sec_where .= ($topic) ? qq|AND tid = '$topic' | : '';
		if ($user) {
			my $tmp_uid = $S->get_uid_from_nick($user);
			$sec_where .= qq|AND aid = '$tmp_uid' |;
		}

		my $maxdays = $args->{'-maxdays'};
		if ($maxdays) {
			$sec_where .= qq|AND TO_DAYS(NOW()) - TO_DAYS(time) <= $maxdays |; 
		}

		$sec_where .= ' ' . $excl_sect_sql_wAND;

		my $maxstories = $S->pref('maxstories');
		my $offset = (($page * $maxstories) - $maxstories) if $page;
		if ($S->{UI}->{VARS}->{allow_story_hide}) {
		($rv, $sth) = $S->db_select({
			ARCHIVE => 0,
			DEBUG => $DEBUG,
			WHAT => qq|s.sid as sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
			FROM => "(stories s LEFT OUTER JOIN viewed_stories v on s.sid = v.sid and v.uid = $S->{UID}) LEFT JOIN $db_name u ON s.aid = u.uid",
			WHERE => qq|(displaystatus >= 0) and (v.hide < 1 or v.hide is null) $sec_where|,
			ORDER_BY => 'time desc',
			LIMIT => $maxstories,
			OFFSET => $offset });
		} else {
		($rv, $sth) = $S->db_select({
			ARCHIVE => 0,
			DEBUG => $DEBUG,
			WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
			FROM => 'stories s LEFT JOIN users u ON s.aid = u.uid',
			WHERE => qq|displaystatus >= 0 $sec_where|,
			ORDER_BY => 'time desc',
			LIMIT => $maxstories,
			OFFSET => $offset});
		};
		unless ($rv) {
			return [];
		}

		my $count = $maxstories;
		
		while (my $story = $sth->fetchrow_hashref) {
			#warn "In Elements, getting commentcount for $story->{sid}\n";
			$story->{commentcount} = $S->_commentcount($story->{sid});	
			$story->{archived} = 0;
			push (@{$return_stories}, $story);
			$count --;
		}
		if ($S->{HAVE_ARCHIVE} && ($count > 0) && ( !exists($args->{'-sid'}))) {
			$sth->finish();
			($rv, $sth) = $S->db_select({
				ARCHIVE => 0,
				DEBUG => $DEBUG,
				WHAT => qq|count(sid)|,
				FROM => 'stories',
				WHERE => qq|displaystatus >= 0 $sec_where| });
			my $maxoffset = $sth->fetchrow;
			$sth->finish();
			my $newoffset = $offset - $maxoffset + ($maxstories - $count);
			($rv, $sth) = $S->db_select({
				ARCHIVE => 1,
				DEBUG => $DEBUG,
				WHAT => qq|sid, tid, aid, u.nickname AS nick, title, dept, $date_format AS ftime, introtext, bodytext, section, displaystatus|,
				FROM => "stories s LEFT JOIN $db_name u ON s.aid = u.uid",
				WHERE => qq|displaystatus >= 0 $sec_where|,
				ORDER_BY => 'time desc',
				LIMIT => $count,
				OFFSET => $newoffset
			});
			
			while (my $story = $sth->fetchrow_hashref) {
				#warn "In Elements, getting commentcount for $story->{sid}\n";
				$story->{commentcount} = $S->_commentcount($story->{sid});	
				$story->{archived} = 1;
				push (@{$return_stories}, $story);
			}
		}
		$sth->finish;
	
		return $return_stories;
	}

	unless ($rv) {
		return [];
	}
	
	while (my $story = $sth->fetchrow_hashref) {
		#warn "In Elements, getting commentcount for $story->{sid}\n";
		$story->{commentcount} = $S->_commentcount($story->{sid});	
		$story->{archived} = $S->_check_archivestatus($story->{sid});
		push (@{$return_stories}, $story);
	}
	#warn "Leaving.\n";
	$sth->finish;
	
	return $return_stories;
}


=over 4

=item $S->get_sids($params)

=item $S->story_data($sids)

These are a replacement for getstories() and should be used instead. It is saner,
cleaner, uses a per-request cache, and tries to reduce the database load quite
a bit more.

$S->story_data() takes an arrayref of story IDs and checks the cache, falling
through to the database if necessary and filling the cache, and returns an
arrayref containing a hashref for each story (as getstories() did) including
all fields from the stories table, the read comments and hotlist information,
and the comment counts.

$S->get_sids() takes a hashref of options, and does all the permission checking
and does a select on the stories table (joined with viewed_stories if the
hotlisted flag is set) and returns an arrayref of story IDs suitable for
passing directly to $S->story_data(). It requires you to be more specific than
getstories() did, but because of this it doesn't try to be "smart" and prevent
you from getting exactly what you want. 

=over 4

=head2 get_sids() parameters

The hash keys listed below are recognized get_sids() options.

Any of the values in the hashref may be strings or arrayrefs; if arrayrefs, SQL
IN() will be used instead of = so you can filter on multiple values at once.
Exceptions to this are indicated below. To not filter on any of the possible
parameters, simply leave them unset.

=item aid

Fetches stories only by the user(s) whose UID(s) are given here. If both aid
and user are provided, aid is used.

=item user

Fetches stories only by the user(s) whose nickname(s) are given here. If both
aid and user are provided, aid is used.

=item perm_override

Turns off permission checking for disallowed sections. This is a true/false
flag only. (True = do not check permissions)

=item section

The particular section(s) and subsections you want to retrieve stories from.
This also recognizes the pseudo-section __all__ and fetches the appropriate
sections.

=item hotlisted

When true, only stories that are hotlisted by the current user are fetched.
This is a true/false flag only.

=item page

Which index page to return. This will generally not be used at the same time as
limit and offset (below) as it sets them itself using the system defaults for
maxstories. If offset is also set, page will be ignored. This cannot be an
arrayref.

=item limit

The maximum number of SIDs to return. If not set, maxstories is used; if set to
zero, removes the limit and all matching SIDs will be returned. This cannot be
an arrayref.

=item offset

The number of SIDs to skip before starting to return any. If this is not set,
the offset is calculated from the page parameter. If the page parameter is not
set, there is no offset and SIDs are returned starting with the first one that
matches. This cannot be an arrayref.

=item sid

The particular SID(s) to fetch. This is included so the permissions checking
can be done if you know the SID already (story_data doesn't check permissions).

=item tid

The topic ID(s) of the stories you want.

=item displaystatus

The display status of the stories you want to display. Note that you must be
explicit; if you want front page stories, you'd use a value of 0, but if you
want to display a section page (which includes the stories posted to the front
page but filed in that section) you would use a value of [0,1] - the arrayref
containing both displaystatuses you want.  The same goes for queued stories:
[-2,-3] would get you stories in both the voting and edit queues.

=item commentstatus

The numeric comment status (read only = 1, disabled = -1, enabled = 1) of the
stories.

=item totalvotes

The number of moderation votes this story received in the moderation queue.
Note that this is an exact comparison, not a greater than/less than comparison.

=item score

The current (or final, for stories not in the queue) moderation score the story
received. Note that this is an exact comparison, not a greater than/less than
comparison.

=item attached_poll

The poll ID (qid) of the poll associated with the story.

=item sent_email

The status of the story: 1 = email was sent to the author informing them their
story was posted or dropped; 0 = email wasn't sent (for a variety of reasons)

=item edit_category

The edit category of the story. This is only useful if your site is using edit
categories (usually done only with a closed queue). See the Scoop Admin Guide
for details on edit categories.

=item where

Anything you would like to add to the WHERE clause. Note that this is just
appended to what's already there, so you should put an ' AND ' at the
beginning. If the WHERE clause starts with ' AND ', that is removed, so better
to put it there than leave it off.

=item from

Anything you would like to add to the FROM clause (such as joins to another
table). This is appended to what's already there with a space inserted between
the two parts. The stories table is aliased to 's' and (if the hotlisted
parameter is true) the viewed_stories table is aliased to 'v'.

=back

The two functions will generally be used together, but if you already know the
SID(s) you want, story_data() can be used alone.

=back

=cut

# this is the old get_sids function, hacked up to allow fetching either sids or
# ids. get_sids is now a wrapper function, along with get_story_ids that calls
# _get_sids_or_id setting the appropriate flag

sub get_sids {
	my $S = shift;
	my $params = shift;
	return $S->_get_sids_or_id($params, 0);
	}

sub get_story_ids {
	my $S = shift;
	my $params = shift;
	return $S->_get_sids_or_id($params, 1);
	}

sub _get_sids_or_id {
	my $S = shift;
	my $params = shift;
	my $fl = shift;

	my $sids;
	my $q_uid = $S->dbh->quote($S->{UID});

	warn "(get_sids) starting..." if $DEBUG;
	my $cfetch;
	my $op = $S->cgi->param('op');
	if(($op eq 'main' || $op eq 'section') && !$params->{user} && ($S->pref('maxstories') == 15) && ($params->{page} < 5)){
                $cfetch = "${op}-$params->{page}";
                $cfetch .= "_" . $S->pref('maxstories');
                $sids = $S->cache->fetch($cfetch);
                }
        elsif ($params->{hotlisted}){
	#if ($params->{hotlisted}){
                $cfetch = "hotlisted_" . $S->{UID};
                $sids = $S->cache->fetch($cfetch);
                }
        if ($sids) {
                undef $sids if ($sids eq '0E0');
                return $sids;
                }

	#aid overrules user
	$params->{aid} = $S->get_uid_from_nick($params->{user}) if ($params->{user} && !$params->{aid});

	# set up the SQL query
	my ($joined, $where, $from);
	my ($disallowed_sections, $excl_from_all);
	my @allowed_auto_fields = qw(sid tid aid section displaystatus commentstatus totalvotes score attached_poll sent_email edit_category id);
	# most story table fields; some excluded because they're more suitable
	# for search than get_sids

	$from = 'stories s';

	# the where clauses...
	# perhaps...?
	if($params->{section} eq 'Diary' && $params->{aid}){
		delete($params->{section});
		}
	unless ( $params->{perm_override} ) {
		# do perm-checking here
		warn "(get_sids) checking permissions..." if $DEBUG;
		$disallowed_sections = $S->get_disallowed_sect_sql('norm_read_stories');
	}
	# sections excluded from "All"
	if ( $params->{section} eq '__all__' ) {
		$excl_from_all = $S->excluded_from_all_stories();
		delete($params->{section});
	}
	# SQL to make sure we get stories from subsections as needed
        if( $S->var('enable_subsections') && $params->{section} ){
                if ( ref($params->{section}) eq 'ARRAY' ) {
                        my @sectlist;
                        for(@{$params->{section}}){
                                push(@sectlist,$S->get_inheritable_sect_array($_));
                        }
                        $params->{section}=[@sectlist];
                }else{
                        $params->{section}=$S->get_inheritable_sect_array($params->{section});
                }
        }
	$where = $disallowed_sections;
	$where .= ( $where && $excl_from_all ) ? ' AND ' : '';
	$where .= $excl_from_all;

	if ( $params->{hotlisted} ) {
		# we want hotlisted stories
		warn "(get_sids) looking for hotlisted stories" if $DEBUG;
		$from .= " LEFT JOIN viewed_stories v ON (s.sid = v.sid AND v.uid = $q_uid)";
		$where .= " AND v.hotlisted = 1";
	}

	# gotta do some special dkos specific stuff for diary pages. :-/
	# grumble grumble
	#warn "!!!! SECTION STUFF !!!! Section: $params->{section} AID: $params->{aid}\n" if $S->{UID} == 3406;
	#foreach my $secdebug (@$params->{section}){
	#	warn "SECTION = $secdebug\n" if $S->{UID} == 3406;
	#    }
	#if($params->{section} eq 'Diary' && $params->{aid}){
	#	delete($params->{section});
	#	warn "THIS REALLY OUGHT TO WORK!!!\n";
	#    }
	# add WHERE info for the auto fields
	foreach my $auto (@allowed_auto_fields) {
		if ( ref($params->{$auto}) eq 'ARRAY' ) {
			my $sql_auto = join(', ', map {$S->dbh->quote($_)} (@{$params->{$auto}}));
			$where .= " AND $auto IN ($sql_auto)";
		} elsif ( defined($params->{$auto}) ) {
			$where .= " AND $auto = " . $S->dbh->quote($params->{$auto});
		}
	}

	my $main_db = $S->{CONFIG}->{db_name};
	# add WHERE info for tags
	if ($params->{tag}) {
		$where .= qq| AND t.tag = | . $S->dbh->quote($params->{'tag'}); 
		$from .= qq| LEFT JOIN ${main_db}.story_tags t ON (s.sid = t.sid)|;
	}
	
	$where .= $params->{where} if $params->{where};
	$from .= " " . $params->{from} if $params->{from};

	$where =~ s/^ AND //;
	# make sure it doesn't start with an AND...

	my $limit = (defined($params->{limit})) ? $params->{limit} : $S->pref('maxstories');
	# set limit to zero to disable limits, leave unset to get maxstories
	my $page = $params->{page} || 1;
	my $offset = $params->{offset} || ($page-1) * $limit;
	my $what = ($fl) ? 's.id' : 's.sid';

	my ($rv,$sth) = $S->db_select({
		DEBUG => $DEBUG,
		WHAT => $what,
		FROM => $from,
		WHERE => $where,
		ORDER_BY => 's.time desc',
		LIMIT => $limit,
		OFFSET => $offset
	});


	while ( my ($sid) = $sth->fetchrow() ) {
		push @$sids,$sid;
	}
	my $fetched = $rv;
	$sth->finish();

	#FIXME don't forget the archive!
	if ( ($fetched < $limit || $limit == 0) && $S->{HAVE_ARCHIVE} ) {
		warn "(get_sids) didn't get all the stories... checking archive db" if $DEBUG;
		my $archfrom = "stories s";
		if ($params->{hotlisted}){
			$archfrom .= " LEFT JOIN ${main_db}.viewed_stories v ON (s.sid = v.sid AND v.uid = $q_uid)"
			}
		if ($params->{tag}){
			$archfrom .= " LEFT JOIN ${main_db}.story_tags t ON (s.sid = t.sid)";
			}
		# calculate the offset within the archive db
		($rv,$sth) = $S->db_select({
			DEBUG => $DEBUG,
			WHAT => 'count(s.id)',
			FROM => $archfrom,
			WHERE => $where,
			ORDER_BY => 's.time desc'
		});
		my $maxoffset = $sth->fetchrow;
		$sth->finish();
		my $newoffset = $offset - $maxoffset + $fetched;

		my $newfrom = $from;
		if ( $params->{hotlisted} ) {
			# we want hotlisted stories
			# have to join to viewed_stories in the main db to get them
			if ( lc($S->{CONFIG}->{DBType}) eq 'mysql' ) {
				$newfrom =~ s/viewed_stories/$S->{CONFIG}->{db_name}.viewed_stories/;
			}
		}

		$limit = $limit - $fetched if $limit != 0;

		($rv,$sth) = $S->db_select({
			DEBUG => $DEBUG,
			ARCHIVE => 1,
			WHAT => $what,
			FROM => $newfrom,
			WHERE => $where,
			ORDER_BY => 's.time desc',
			LIMIT => $limit,
			OFFSET => $newoffset
		});

		while ( my ($sid) = $sth->fetchrow() ) {
			push @$sids,$sid;
		}
		$sth->finish();
	}

	if ( $sids ) { warn "(get_sids) returning " . join(', ', @$sids) if $DEBUG; }
	if ($cfetch){
                my $store = $sids || "0E0";
		if($cfetch =~ /^hotlisted/){
			$S->cache->store($cfetch, $store, "+1h");
			}
		else {
                	$S->cache->store($cfetch, $store, "+5m");
			}
                }

	return $sids;
}

sub story_data {
	my $S = shift;
	my $sids = shift;

	my $return_stories;
	my $q_uid = $S->dbh->quote($S->{UID});

	warn "(story_data) starting..." if $DEBUG;
        my $main_db = $S->{CONFIG}->{db_name};
	my $sids_to_fetch;
	
	foreach (@$sids) {
		if($S->{UID} < 0){
                        # stick the anon story cache into STORY_CACHE while
                        # we're looking at it, I guess
                        $S->{STORY_CACHE}->{$_} = $S->story_cache->asd($_);
                        }
		push @$sids_to_fetch,$_ unless ($S->{STORY_CACHE}->{$_});
	}

	if ( $sids_to_fetch ) {
		warn "(story_data) getting @$sids_to_fetch from database" if $DEBUG;
		my $sids_sql = join(',', map { $S->dbh->quote($_) } (@$sids_to_fetch) );
	
	
		# build the SQL query for those stories not in the cache
		my $date_format = $S->date_format('time');
	
		my ($rv,$sth) = $S->db_select({
			DEBUG => $DEBUG,
			WHAT => "s.*,v.hotlisted,v.lastseen,v.highest_idx,u.nickname as nick,$date_format as ftime,count(c.cid) as comments",
			FROM => "stories s LEFT JOIN ${main_db}.users u ON s.aid = u.uid LEFT JOIN ${main_db}.viewed_stories v ON (s.sid = v.sid AND v.uid = $q_uid) LEFT JOIN comments c ON s.sid = c.sid",
			WHERE => "s.sid IN ($sids_sql)",
			GROUP_BY => 's.sid'
		});
	
		while ( my $story = $sth->fetchrow_hashref() ) {
			# cache them
			delete $S->{STORY_CACHE}->{$story->{sid}};
                        $S->{STORY_CACHE}->{$story->{sid}} = $story;
			# for anon, too
			$S->story_cache->asd($story->{sid}, $story);
		}
	}

	$sids_to_fetch = ();
	foreach (@$sids) {
		# for some reason, the way that's commented out doesn't seem
		# to be working.
		push @$sids_to_fetch,$_ unless ($S->{STORY_CACHE}->{$_});
#s ( grep { /^$_$/ } (keys %{$S->{STORY_CACHE}}) );
		# checking to see if we got them all - if not, we look in the archive
	}
	if ( $sids_to_fetch && $S->{HAVE_ARCHIVE} ) {
		warn "(story_data) getting @$sids_to_fetch from archive database" if $DEBUG;
		my $sids_sql = join(',', map { $S->dbh->quote($_) } (@$sids_to_fetch) );
	
	
		# build the SQL query for those stories not in the cache
		my $date_format = $S->date_format('time');
		my $db_name = $S->{CONFIG}->{db_name} . ".users";	
		my ($rv,$sth) = $S->db_select({
			DEBUG => $DEBUG,
			ARCHIVE => 1,
			WHAT => "s.*,v.hotlisted,v.lastseen,v.highest_idx,u.nickname as nick,$date_format as ftime,count(c.cid) as comments",
			FROM => "stories s LEFT JOIN $db_name u ON s.aid = u.uid LEFT JOIN ${main_db}.viewed_stories v ON (s.sid = v.sid AND v.uid = $q_uid) LEFT JOIN comments c ON s.sid = c.sid",
			WHERE => "s.sid IN ($sids_sql)",
			GROUP_BY => 's.sid'
		});
	
		while ( my $story = $sth->fetchrow_hashref() ) {
			$story->{archived} = 1;
			# cache them
			$S->{STORY_CACHE}->{$story->{sid}} = $story;
			$S->story_cache->asd($story->{sid}, $story);
		}
	}

	foreach (@$sids) {
		# assume they were given to us in the correct order
		# method to recover from the story in the cache being deleted
		# while we were getting the story data. Shouldn't happen too
		# much though, only when someone's edited a story while we
		# were loading the page, but better safe that sorry
		push @$return_stories,$S->{STORY_CACHE}->{$_} if $S->{STORY_CACHE}->{$_};
		warn "(story_data) returning $_" if $DEBUG;
	}

	return $return_stories;
}




# Fetch and SQL-format any optional sections to exclude from 
# the "__all__" section
sub excluded_from_all_stories {
	my $S = shift;
	
	my @sections = split /,\s*/, $S->var('sections_excluded_from_all');
	my $sql;
	
	foreach my $sec (@sections) {
		next unless (exists $S->{SECTION_DATA}->{$sec});
		$sql .= qq| AND section != '$sec'|;
	}
	
	return $sql;
}

sub story_nav {
	my $S = shift;
	my $sid = shift;
	
	# Check for nav bar on/off
	return '' if ($S->{UI}->{VARS}->{disable_story_navbar});

	# if they don't have permission to view the story, they won't see the story, so the
	# nav bar looks out of place.  Return ''
	unless( $S->have_section_perm( 'norm_read_stories', $S->_get_story_section($sid) ) ) {
		return '';
	}

	my $q_sid = $S->dbh->quote($sid);
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'time',
		FROM => 'stories',
		WHERE => qq|sid = $q_sid|});
	
	my $story = $sth->fetchrow_hashref;
	$sth->finish;

	#warn "STIME: $story->{time}\n";

	my $excl_sect_sql = ' AND ' . $S->get_disallowed_sect_sql('norm_read_stories');
	$excl_sect_sql = '' if( $excl_sect_sql eq ' AND ' );
	
	# If section is an section in the story_nav_bar_sections var
	# then only display stories from that section, otherwise
	# only display stories that are not in any of those sections
	my $sections = $S->{UI}->{VARS}->{'story_nav_bar_sections'} . ',';
	my $section = $S->_get_story_section($sid);
	if ($sections =~ /$section/) 
	{ 
		$section = $S->dbh->quote($section);
		$excl_sect_sql .= qq|AND section = $section|;
	} else {
		my @section_list = split /,\s*/, $sections;
		foreach $section (@section_list) {
			next unless (exists $S->{SECTION_DATA}->{$section});
			$section = $S->dbh->quote($section);
			$excl_sect_sql .= qq|AND section != $section|;
		}
	}
	
	($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		DEBUG => $DEBUG,
		WHAT => 'sid, title',
		FROM => 'stories',
		WHERE => qq|time < '$story->{time}' AND displaystatus >= 0 $excl_sect_sql|,
		ORDER_BY => 'time desc',
		LIMIT => 1});
	
	my $last = undef;
	if ($last = $sth->fetchrow_hashref)
	{
		$last->{commentcount} = $S->_commentcount($last->{sid});
	}
	$sth->finish;
	
	($rv, $sth) = $S->db_select({
		DEBUG => $DEBUG,
		WHAT => 'sid, title',
		FROM => 'stories',
		WHERE => qq|time > '$story->{time}' AND displaystatus >= 0 $excl_sect_sql|,
		ORDER_BY => 'time asc',
		LIMIT => 1});

	my $next = undef;
	if ($next = $sth->fetchrow_hashref)
	{
		$next->{commentcount} = $S->_commentcount($next->{sid});
	}
	$sth->finish;
	
	my $nav = $S->{UI}->{BLOCKS}->{navbar};
	my $navkeys;
			
	if ($last) {
		unless( $S->have_section_perm( 'hide_read_comments',$S->_get_story_section($last->{sid}) ) ) {
			$last->{comments} = $S->{UI}->{BLOCKS}->{navbar_comments};
			$last->{comments} = s/%%num%%/$last->{commentcount}/g;
		}
		$navkeys->{'last'} = $S->interpolate($S->{UI}->{BLOCKS}->{navbar_last},$last);
	}

	if ($last && $next) {
		$navkeys->{sep} = $S->{UI}->{BLOCKS}->{navbar_sep};
	}

	if ($next) {
		unless( $S->have_section_perm( 'hide_read_comments',$S->_get_story_section($next->{sid}) ) ) {
			$next->{comments} = $S->{UI}->{BLOCKS}->{navbar_comments};
			$next->{comments} = s/%%num%%/$next->{commentcount}/g;
		}
		$navkeys->{'next'} = $S->interpolate($S->{UI}->{BLOCKS}->{navbar_next},$next);
	}

	return $S->interpolate($nav,$navkeys);
}



sub recent_topics {
	my $S = shift;
	my $images = '%%imagedir%%%%topics%%';
	my ($rv, $sth) = $S->db_select({
		WHAT => 'tid, sid',
		FROM => 'stories',
		WHERE => 'displaystatus >= 0',
		ORDER_BY => 'time desc',
		LIMIT => qq|$S->{UI}->{VARS}->{recent_topics_num}|});

	my ($last_topics, $topic);
	while (my $tid = $sth->fetchrow_hashref) {
		$topic = $S->get_topic($tid->{tid});
		if( $topic ) {
			$last_topics .= qq|
				<A HREF="%%rootdir%%/story/$tid->{sid}"><IMG SRC="$images/$topic->{image}" WIDTH="$topic->{width}" HEIGHT="$topic->{height}" ALT="$topic->{alttext}" BORDER=0></A>&nbsp;|;
		} else {
			$last_topics = '';
		}
	}

	$sth->finish;
	
	return $last_topics;
}

sub story_mod_display {
	my $S = shift;
	my $sid = shift;
	
	# See if we've already moderated this story..
	my ($disp_mode, $mod_data) = $S->_mod_or_show($sid);
	
	my ($form, $type);
	my $formkey = $S->get_vote_formkey();

	#If we're go to moderate this one....
	if ($disp_mode eq 'moderate') {
		if ( $S->{UI}->{VARS}->{story_auto_vote_zero} ) {
			$S->save_vote ($sid, '0', 'N');
		} else {
			$form = $S->{UI}->{BLOCKS}->{vote_console};

			my $form_txt = $S->{UI}->{BLOCKS}->{story_vote_form};
			$form_txt =~ s/%%formkey%%/$formkey/;
			$form_txt =~ s/%%sid%%/$sid/;
			$form =~ s/%%vote_form%%/$form_txt/;
			$type = 'content';
		}
		#otherwise, make the stats box
	} elsif ($disp_mode eq 'edit') {
		$type = 'content';
		my $spam_form;
		if ( ($S->_get_user_voted($S->{UID}, $sid) == 0) && 
		     ($S->{UI}->{VARS}->{use_anti_spam})) {
			$spam_form = $S->{UI}->{BLOCKS}->{edit_instructions_abuse};
			$spam_form =~ s/%%formkey%%/$formkey/;
			$spam_form =~ s/%%sid%%/$sid/;
		} else {
			$spam_form = '';
		}
		$form = "$S->{UI}->{BLOCKS}->{edit_instructions}";
		$form =~ s/%%spam_form%%/$spam_form/;
	} else {
		if ($S->{UI}->{VARS}->{story_auto_vote_zero} ) {
			$S->save_vote ($sid, '0', 'N');
		}
		
		$type = 'box';
		$form = $S->_moderation_list($sid);
	}
	
	return ($type, $form);
}

sub get_vote_formkey {
	my $S = shift;
	
	my $user = $S->user_data($S->{UID});

	Crypt::UnixCrypt::crypt($user->{'realemail'}, $user->{passwd}) =~ /..(.*)/;
	my $element = qq|<INPUT TYPE="hidden" NAME="formkey" VALUE="$1">|;	
	
	return $element;
}

sub _mod_or_show {
	my $S = shift;
	my $sid = shift;

	my $quotesid = $S->{DBH}->quote($sid);	
	my ($rv, $sth) = $S->db_select({
		DEBUG => $DEBUG,
		WHAT => 'time, vote',
		FROM => 'storymoderate',
		WHERE => qq|sid = $quotesid AND uid = $S->{UID}|});
	
	my ($returncode, $mod_data);
	if ($rv >= 1 && $rv ne '0E0') {
		#warn "Got existing vote!";
		$returncode = 'show';
		$mod_data = $sth->fetchrow_hashref;
	} else {
		#warn "No vote.";
		$returncode = 'moderate';
	}
	$sth->finish;
	
	($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'aid, displaystatus',
		FROM => 'stories',
		WHERE => qq|sid = $quotesid|});

	my ($aid, $displaystatus) = $sth->fetchrow_array() if ($rv && $rv ne '0E0');

	if ($aid eq $S->{UID} && $displaystatus != -3) {
		$returncode = 'show';
	} elsif ($displaystatus == -3) {
		$returncode = 'edit';
	}
	
	$sth->finish;

	return ($returncode, $mod_data);
}

sub _moderation_list {
	my $S = shift;
	my $sid = shift;
	
	return $S->box_magic('mod_stats', $sid);
}

sub _get_story_mods {
	my $S = shift;	
	my $sid = shift;
	my $date_format = $S->date_format('time');

	my $quotesid = $S->{DBH}->quote($sid);	
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => qq|uid, $date_format AS ftime, vote, section_only|,
		FROM => 'storymoderate',
		WHERE => qq|sid = $quotesid|,
		ORDER_BY => 'time desc'});
	
	return $sth;
}
#'

sub _check_for_story {
	my $S = shift;
	my $sid = shift;

	# if its cached, return it.
	return 1 if ( $S->{sid_cache}->{$sid} );

	# otherwise look for it, and cache if it exists	
	my $quotesid = $S->{DBH}->quote($sid);
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'sid',
		FROM => 'stories',
		WHERE => qq|sid = $quotesid|,
		LIMIT => 1});
	my $num = $sth->fetchrow;
	$sth->finish;
	if ($num) {
		
		# cache it, then return 1, cause it exists
		$S->{sid_cache}->{$sid} = 1;
		$S->{qid_cache}->{$sid} = 0;

		return 1;
	}
	
	return 0;
}


sub author_control_display {
	my $S     = shift;
	my $story = shift;
	my $form;
	
	# if the displaystatus mode is set to editing, and the author is viewing
	# then display the edit story button.
	
	if ( ($story->[2] eq $S->{UID}) && ($story->[11] <= '-2') && $S->have_perm('edit_own_story') ) {
		$form = $S->{UI}->{BLOCKS}->{author_edit_console};
		my $edit_button;
		my $edit_instructions;
		if ($story->[11] == '-3') {
			$edit_button = '<INPUT TYPE="Submit" NAME="edit" VALUE="Edit Story">';
			$edit_instructions = $S->{UI}->{BLOCKS}->{author_edit_instructions};
		};
		
		$story->[6] =~ s/"/&quot;/g;
		$story->[7] =~ s/"/&quot;/g;
		$story->[3] =~ s/"/&quot;/g;

		my $qid = $S->get_qid_from_sid($story->[0]);
		my $author_box_txt = qq|
			%%norm_font%%
			<FORM NAME="editstory" ACTION="%%rootdir%%/" METHOD="POST">
				$edit_button
				<INPUT TYPE="Submit" NAME="delete" VALUE="Cancel Submission">
				<INPUT TYPE="checkbox" NAME="confirm_cancel" VALUE="1"> 
				Confirm cancel?
				<INPUT TYPE="hidden" NAME="edit_in_queue" VALUE="1">
				<INPUT TYPE="hidden" NAME="op" VALUE="submitstory">
				<INPUT TYPE="hidden" NAME="sid" VALUE="$story->[0]">
				<INPUT TYPE="hidden" NAME="preview" VALUE="1">
				<INPUT TYPE="hidden" NAME="tid" VALUE="$story->[1]">
				<INPUT TYPE="hidden" NAME="title" VALUE="$story->[3]">
				<INPUT TYPE="hidden" NAME="introtext" VALUE="$story->[6]">
				<INPUT TYPE="hidden" NAME="section" VALUE="$story->[10]">
				<INPUT TYPE="hidden" NAME="time" VALUE="$story->[5]">
				<INPUT TYPE="hidden" NAME="bodytext" VALUE="$story->[7]">
				<INPUT TYPE="hidden" NAME="qid" VALUE="$qid)">
				<INPUT TYPE="hidden" NAME="retrieve_poll" VALUE="1">
			</FORM>
			%%norm_font_end%%|;
		$form =~ s/%%author_edit_form%%/$author_box_txt/;
		$form =~ s/%%author_edit_instructions%%/$edit_instructions/;
	}
	
	return $form;
}

1;
