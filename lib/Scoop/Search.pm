=head1 Search.pm

This is the main module to drive searching in scoop.  Its called anytime you go to op=search, and the main
access point here is though the search subroutine

=head1 Functions

=cut 

package Scoop;
use strict;
my $DEBUG = 0;


=pod

=over 4

=item *
search()

This is the main search function.  It controls the overall display of the search page (Boxes, Content, etc)
, and calls all the appropriate
functions to populate the page with the answers to your search.  This is the only function in Search.pm that
should be called from outside of this module.  The rest are specific to displaying parts of the search, and
essentially useless for other uses.

=back

=cut

sub search {
	my $S = shift;

	my $args = $S->{CGI}->Vars;
	my $result_count = $args->{count} || 30;

	$S->{UI}->{BLOCKS}->{subtitle} = 'Search';

	# Check res count
	if ($result_count > 50) {
		$result_count = 50;
	} 
	if ($result_count < 1) {
		$result_count = 1;
	}
	
	$args->{count} = $result_count;
	
	$args->{count} = 15 if ($args->{op} eq 'xmlsearch');
	
	my $get_num = $result_count + 1;
	
	$args->{type}       ||= 'story';
	$args->{offset}     ||= 0;
	
	my $offset;
	if ($args->{last}) {
		$offset = $args->{offset} - $args->{count};
	} elsif ($args->{next}) {
		$offset = $args->{offset} + $args->{old_count};
	} else {
		$offset = 0;
	}
	
	$offset = 0 if ($offset < 0);
	
	$args->{offset} = $offset;

	$args->{string} ||= $args->{query_text};
	# clip string down if need be
	if(length($args->{string}) > 512){
		$args->{string} = substr($args->{string},0,512);
		}
	
	# Put the search crippling stuff here for now
	if(($args->{type} eq 'story' || $args->{type} eq 'comment' || $args->{tyype} eq 'polls' || $args->{type} eq 'diary') && ($args->{string} && $S->{UI}->{VARS}->{crippled_search})){
		my $search_string = $S->urlify($args->{string});
                my $safe_string = $S->filter_subject($args->{string});
		my $safetype = $S->filter_subject($args->{type});
		my $cripblock = $S->{UI}->{BLOCKS}->{cripple_search_block};
		$cripblock =~ s/%%STRING%%/$search_string/g;
		$cripblock =~ s/%%DISPLAY_STRING%%/$safe_string/g;
		$S->{UI}->{BLOCKS}->{CONTENT} = qq|
	       <TABLE WIDTH="100%" BORDER=0 CELLPADDING=0 CELLSPACING=0>
	       <TR BGCOLOR="%%title_bgcolor%%">
	       <TD>%%title_font%%$safetype search results%%title_font_end%%</TD>
	        </TR>|;
		$S->{UI}->{BLOCKS}->{CONTENT} .= $cripblock;
		$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, 0, 0, 0, 0);
		return;
		}
	# or for that matter, if we're using the external pysearch
        # force archive for comment_by if wayback (or wayfront) is more than
        # 1 week.
        if ($args->{wayfront} > 10080 || $args->{wayback} > 10080){
                $args->{search_archive} = 1;
                }

	# some emergency stuff because the archive is, once again, getting too
	# big for its britches. This is only until I can get a hold of jotter
	# and get it working for real
	if (!$args->{string} && (($args->{type} eq 'comment' && (!$args->{hidden_comments} || ($args->{hidden_comments} && $args->{search_archive}))) || (($args->{type} eq 'story' || $args->{type} eq 'diary') && $args->{search_archive}))){
		$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, 0, 0, 0, 0);
		return;
		}
	
	
	my $query = {};
	#Determine real quick if we're going to hit the search db or not
        if($S->{UI}->{VARS}->{use_seperate_search_db} && (($args->{type} eq 'diary') || ($args->{type} eq 'comment') || ($args->{type} eq 'story')) && $args->{string}){
		$args->{use_seperate_search} = 1;
		}
	
	if($S->{UI}->{VARS}->{use_pysearch} && (($args->{type} eq 'diary') || ($args->{type} eq 'story' || $args->{type} eq 'both' || $args->{type} eq 'comment' || $args->{type} eq 'author' || ($args->{type} eq 'comment_by' && $args->{search_archive}))) && $args->{string}){
		# Make sure some jackass isn't trying to hammer our poor search
		# engine
		my $rip = $S->{REMOTE_IP};
		if(my $stime = $S->cache->fetch("sthrottle_$rip")){
			my $sthrot = $S->{UI}->{VARS}->{search_throttle_time} || 5;
			$stime = time() - $stime; 
			if ($stime < $sthrot) {
				my $r = "Sorry, you may only use the search function every $sthrot seconds. You last searched $stime seconds ago.";
				$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, 0, 0, $r, 0);
				return;
				}
			}
		# Seems best to keep the arg hashes seperate. This way,
		# at least it might be easier to keep things straight.
		my $pyargs = {};
		# Comment searching doesn't work yet. This takes that into
		# account.
		if($args->{type} eq 'comment' || $args->{type} eq 'comment_by'){
			# break out if pysearch comment is not enabled.
			if(!$S->{UI}->{VARS}->{use_comment_pysearch}){
				my $r = "Sorry, comment search with a query string is currently disabled. We hope to have this fixed in the near future.";
				$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, 0, 0, $r, 0);
				return;
				}
			# otherwise, huzzah. We can search. Comment search is
			# handled differently than the rest of the pysearch,
			# though, so we have to do it here with separate
			# functions
			
			# figure out our args.
			# comment by searches need some filterin'
                        if ($args->{type} eq 'comment_by') {
                                my $searchuid = $S->get_uid_from_nick($args->{string});
                                $pyargs->{query} = "uid=$searchuid";
				# to force the archive behavior and all
				#$args->{wayfront} = 20160 unless $args->{wayfront};
				#$args->{wayback} = 40320 if $args->{wayback} == 20160;
                                }
                        else { # normal comment searches go through unmolested
                                $pyargs->{query} = $args->{string};
                                }
			$pyargs->{max} = $args->{count};
			$pyargs->{sortby} = $args->{sortby} || 'time';
			$pyargs->{sortby} = 'subject' if $args->{sortby} eq 'title';
			$pyargs->{wayback} = $args->{wayback} || 1440;
			$pyargs->{wayfront} = $args->{wayfront} || 0;
			# flip wayback and wayfront if they're clearly reversed
			if($pyargs->{wayback} < $pyargs->{wayfront}){
				my $flip = $pyargs->{wayback};
				$pyargs->{wayback} = $pyargs->{wayfront};
				$pyargs->{wayfront} = $flip;
				}
			$pyargs->{offset} = $args->{offset};
			$pyargs->{hidden_comments} = $args->{hidden_comments};
			my $res = $S->pysearch_comment_post($pyargs);
			# for now
			my $results = $res->content;
			#return $results;
			my ($ret, $num_hit) = $S->py_comment_search_parse($pyargs, $results);
			                my $next_page = 1;
                	my $last_page = ($args->{offset} != 0) ? 1 : 0;
                	my $disp_count;
                	if($num_hit < ($args->{count} + 1)){
                        	$next_page = 0;
                        	}
                	# let's see how it looks
                	$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, $next_page, $last_page, $ret, $disp_count);
                	return;
			}
		$pyargs->{query} = $args->{string};
		if($args->{type} eq 'both'){
			$pyargs->{division} = $args->{type};
			}
		else {
			$pyargs->{division} = ($args->{type} eq 'story') ? "stories" : 'diaries';
			}
		if($args->{type} eq 'author'){
			$pyargs->{division} = 'both';
			$pyargs->{query} = "author=$args->{string}";
			}
		$pyargs->{max} = $args->{count};
		# These are now in the form.
		$pyargs->{sortby} = $args->{sortby} || 'time';
		$pyargs->{wayback} = $args->{wayback} || 1440;
		$pyargs->{wayfront} = $args->{wayfront} || 0;
		if($pyargs->{wayback} < $pyargs->{wayfront}){
	                my $flip = $pyargs->{wayback};
                        $pyargs->{wayback} = $pyargs->{wayfront};
                        $pyargs->{wayfront} = $flip;
                        }
		# Need to add these to the pysearch, I guess
		$pyargs->{offset} = $args->{offset};
		my $res = $S->pysearch_post($pyargs);
		# meh.
		#return $res->content;
		my $results = $res->content;
		my ($ret, $num_hit) = $S->pysearch_parse($pyargs, $results);
		#return $ret;
		my $next_page = 1;
        	my $last_page = ($args->{offset} != 0) ? 1 : 0;
		my $disp_count;
		if($num_hit < ($args->{count} + 1)){
			$next_page = 0;
			}
		# let's see how it looks
		$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, $next_page, $last_page, $ret, $disp_count);
		return;
		}
	
	$query = $S->_determine_search_q($args);

	my $next_page = 1;
	my $last_page = ($offset != 0) ? 1 : 0;
	my $i = $offset + 1;
	my $stop = 	$offset + $result_count;

	$query->{LIMIT} = $get_num;
	$query->{OFFSET} = $offset;
	$query->{DEBUG} = 0;
	# And set the search flag
	$query->{SEARCH} = ($args->{use_seperate_search}) ? 1 : 0;

	my ($rv, $sth) = $S->db_select($query);
	if ($rv == 0) {
		$rv = 0;
	}
	my $disp_count = $rv;
	if ($rv > $result_count) {
		$disp_count = "more than $result_count"
	}
	
	if ($rv < ($result_count + 1)) {
		$next_page = 0;
	}
	
	#$S->{UI}->{BLOCKS}->{CONTENT} = qq|
	#		<TABLE WIDTH="100%" BORDER=0 CELLPADDING=0 CELLSPACING=0>
	#		<TR BGCOLOR="%%title_bgcolor%%">
	#			<TD>%%title_font%%$args->{type} search results%%title_font_end%%</TD>
	#		</TR>|;

	if ($args->{op} eq 'xmlsearch') {
		return ($sth, $i, $stop);
	}
	
	my ($result_list, $corrected_count) = $S->_format_search($args, $sth, $i, $stop);
	$sth->finish;

	$disp_count = $corrected_count unless( $corrected_count == -1 );

	$S->{UI}->{BLOCKS}->{CONTENT} .= $S->_search_form($args, $next_page, $last_page, $result_list, $disp_count);

	return;
}	


=over 4

=item $S->event_search()

This function handles the event search page (op=eventsearch). Its functionality
should be rolled into the main search op when that's cleaned up, but because
I'm working under a deadline I don't have time to clean up the search code the
way I want to. --janra

=back

=cut

sub event_search {
	my $S = shift;
	my $out = $S->{UI}->{BLOCKS}->{event_search};
	my $where_items;

	# paging
	my $page = $S->cgi->param('page') || 1;
	$page++ if $S->cgi->param('next');
	$page-- if $S->cgi->param('prev');
	my $nextpage = $page + 1;
	my $prevpage = $page - 1;
	my $limit = $S->cgi->param('count') || 30;
	$limit = 50 if $limit > 50;
	my $offset = ( ($page-1) * $limit );

	# keys for the search form
	my $keys = $S->cgi->Vars_cloned();
	$keys->{page} = $page;
	my $num_props = $S->var('event_search_num_options');
	while ( $num_props ) {
		my $props;
		my $line = $S->{UI}->{BLOCKS}->{event_search_property_item};
		$line =~ s/%%num%%/$num_props/g;
		$props->{propertysel} = $S->_event_property_select($num_props);
		$keys->{prop_search} .= $S->interpolate($line,$props);
		$where_items->{$keys->{"property_$num_props"}} = "%" . $keys->{"value_$num_props"} . "%" if ( $keys->{"property_$num_props"} && $keys->{"value_$num_props"} );
		$num_props--;
	}

	# set up where clause
	my $where;
	if ( $keys->{year_start} > 0 ) {
		$where_items->{date_start} = $keys->{year_start};
		if ( $keys->{month_start} > 0 ) {
			$where_items->{date_start} .= ( $keys->{month_start} < 10 ) ? "-0$keys->{month_start}" : "-$keys->{month_start}";
			if ( $keys->{day_start} > 0 ) {
				$where_items->{date_start} .= ( $keys->{day_start} < 10 ) ? "-0$keys->{day_start}" : "-$keys->{day_start}";
			} else {
				$where_items->{date_start} .= '-01';
			}
		} else {
			$where_items->{date_start} .= '-01-01';
		}

		if ( !$keys->{year_end} && !$keys->{month_end} && !$keys->{day_end} ) {
			# Duplicate the start date input if there's no end date set
			$keys->{year_end}  = ($keys->{year_end} > 0 ) ? $keys->{year_end}  : $keys->{year_start};
			$keys->{month_end} = ($keys->{month_end} > 0) ? $keys->{month_end} : $keys->{month_start};
			$keys->{day_end}   = ($keys->{day_end} > 0  ) ? $keys->{day_end}   : $keys->{day_start};
		}

		$where_items->{date_end} = $keys->{year_end};
		if ( $keys->{month_end} > 0 ) {
			$where_items->{date_end} .= ( $keys->{month_end} < 10 ) ? "-0$keys->{month_end}" : "-$keys->{month_end}";
			if ( $keys->{day_end} > 0 ) {
				$where_items->{date_end} .= ( $keys->{day_end} < 10 ) ? "-0$keys->{day_end}" : "-$keys->{day_end}";
			} else {
				$where_items->{date_end} .= '-31';
			}
		} else {
			$where_items->{date_end} .= '-12-31';
		}
	}
	foreach ( keys %$where_items ) {
		next if ($_ eq 'date_end');
		if ( $_ eq 'date_start' ) {
			my $q_start = $S->dbh->quote($where_items->{date_start});
			my $q_end = $S->dbh->quote($where_items->{date_end});

			$where .= " AND ((date_start <= $q_end AND date_end >= $q_start) OR (date_start >= $q_start AND date_start <= $q_end AND date_end = '0000-00-00'))";

		} else {
			$where .= " AND ( property = '$_' AND value LIKE " . $S->dbh->quote($where_items->{$_}) . " )";
		}
	}
	$where =~ s/^ AND //;

	my ($rv,$sth) = $S->db_select({
		DEBUG => $DEBUG,
		WHAT => 'events.eid',
		DISTINCT => '1',
		FROM => 'events left join event_properties using (eid)',
		WHERE => $where,
		ORDER_BY => 'date_start DESC',
		LIMIT => $limit + 1,
		OFFSET => $offset
	});

	# format results
	if ( $rv > 0 ) {
		my $eids;
		while ( my ($eid) = $sth->fetchrow_array() ) {
			push @$eids, $eid;
		}
		if ( $rv >= $limit ) {
			$keys->{next_button} = $S->{UI}->{BLOCKS}->{search_next_button};
			$keys->{next_button} =~ s/%%num%%/$limit/;
			pop @$eids;
		}
		if ( $page > 1 ) {
			$keys->{prev_button} = $S->{UI}->{BLOCKS}->{search_prev_button};
			$keys->{prev_button} =~ s/%%num%%/$limit/;
		}
		$S->get_event($eids);
		foreach (@$eids) {
			my $result = $S->{UI}->{BLOCKS}->{event_search_result_item};
			my $r_keys = $S->get_event($_);
			$keys->{results} .= $S->interpolate($result,$r_keys);
		}
	} else {
		$keys->{results} = "No events found";
	}

	$out = $S->interpolate($out,$keys);
	$out = $S->interpolate($out,$keys);	# a second time because some of the values in $keys 
						# contain references to the cgi variables - which are in $keys
	$out =~ s/%%year_start%%/$keys->{year_start}/; #interpolate doesn't get args to boxes
	$out =~ s/%%month_start%%/$keys->{month_start}/;
	$out =~ s/%%day_start%%/$keys->{day_start}/;
	$out =~ s/%%year_end%%/$keys->{year_end}/;
	$out =~ s/%%month_end%%/$keys->{month_end}/;
	$out =~ s/%%day_end%%/$keys->{day_end}/;
	$S->{UI}->{BLOCKS}->{CONTENT} = $out;
	$S->{UI}->{BLOCKS}->{subtitle} = 'Search %%bars%% Events';
}

=over 4

=item $S->_event_property_select($num)

A selectbox containing each property name as an option. The $num argument is
used in the selectbox's name, as property_$num, to allow multiple property
selectboxes on the same form.

=back

=cut

sub _event_property_select {
	my $S = shift;
	my $num = shift;
	my $select = qq{
		<SELECT name="property_$num" size="1">
			<OPTION value="">----</OPTION>};

	foreach ( sort keys %{$S->{EVENT_PROPERTIES}} ) {
		my $selected = ( $_ eq $S->cgi->param("property_$num") ) ? ' SELECTED' : '';
		$select .= qq|
			<OPTION value="$_"$selected>$S->{EVENT_PROPERTIES}->{$_}->{title}</OPTION>|;
	}

	$select .= qq{
		</SELECT>};
	return $select;
}

=pod 

=over 4

=item *
_search_form($args, $next_page, $last_page, $results, $disp_count);

This function is what really generates the layout of the Search page. $args
is a hash reference to a hash containing all of the Vars from the url. 
$next_page and $last_page are true if the buttons for next page and prev page
should be shown, $results is the results of the query, all html formatted. 
Lastly $disp_count is the number of results found.

=back

=cut

sub _search_form {
	my $S 		= shift;
	my $args	= shift;
	my $next_page	= shift;
	my $last_page 	= shift;
	my $results	= shift;
	my $disp_count	= shift;
		
	my $topic_select = ($S->{UI}->{VARS}->{use_topics}) ? $S->search_topic_select($args->{topic}) : '';
	my $relevance_radio = ($S->{UI}->{VARS}->{use_fulltext_indexes}) ? $S->search_relevance_radio($args->{orderby}) : '';
	my $section_select = (!$S->{UI}->{VARS}->{use_pysearch}) ? $S->search_section_select($args->{section}) : ''; # not real useful with pysearch
	my $search_type_select = $S->search_type_select($args->{type});
	my $phrasebox;
	if($S->{UI}->{VARS}->{use_fulltext_indexes}){
		$phrasebox = "&nbsp;&nbsp;<input type=checkbox name=phrase value=true";
		$phrasebox .= ($args->{phrase})?' CHECKED>':'>';
		$phrasebox .= " as Phrase";
	}

        # blank out default results
        my $getstring = $S->apache->args();
        # weird hack, but at least it works
        if (!$getstring && $S->cgi->param('caller_op') eq 'search'){
		$results = '';
		$next_page = 0;
                }

	# pysearch stuff
	my $wayback;
	my $wayfront;
	my $sortby;
	my $wbsel = {};
	my $wfsel = {};
	my $sortsel = {};
	my $rchk;
	if($S->{UI}->{VARS}->{use_pysearch}){
		# stealing a page from further down
		$args->{wayback} ||= ($S->cgi->param('caller_op') eq 'user') ? 10080 : 20160;
	        $wbsel->{$args->{wayback}} = " selected";
        	$wfsel->{$args->{wayfront}} = " selected";
        	$sortsel->{$args->{sortby}} = " selected";
		$rchk = ($args->{" rev"}) ? 'checked = "checked"' : '';
		# figure out what options are checked while we're at it
		$sortby = qq|<b>Sort By:</b> <select name="sortby" size=1>
			<option value="relevance"$sortsel->{relevance}>Relevance<option value="time"$sortsel->{time}>Time<option value="impact"$sortsel->{impact} >Impact<option value="recommend"$sortsel->{recommend} >Recommend<option value="comments"$sortsel->{comments} >Comments<option value="title"$sortsel->{title} >Title<option value="author"$sortsel->{author}>Author<option value="cid"$sortsel->{cid}>Cid *<option value="nrec"$sortsel->{nrec}>Recommends *<option value="ntroll"$sortsel->{ntroll}>Troll Ratings *</select>
			<!-- Reverse? <input type="checkbox" name =" rev" $rchk> -->
			|;
		$wayback = qq|
			<b>From:</b> <select name="wayback" size=1
><option value="0"$wbsel->{0} >now<option value="60"$wbsel->{60} >1 hour<option value="180"$wbsel->{180} >3 hour<option value="360"$wbsel->{360} >6 hours<option value="720"$wbsel->{720} >12 hours<option value="1440"$wbsel->{1440} >1 day<option value="2880"$wbsel->{2880} >2 days<option value="4320"$wbsel->{43200} >3 days<option value="5760"$wbsel->{5760} >4 days<option value="7200"$wbsel->{7200} >5 days<option value="8640"$wbsel->{8640} >6 days<option value="10080"$wbsel->{10080} >1 week<option value="20160"$wbsel->{20160} >2 weeks<option value="40320"$wbsel->{40320} >4 weeks<option value="131040"$wbsel->{131040} >1 quarter<option value="262080"$wbsel->{262080} >6 months<option value="525600"$wbsel->{525600} >1 year<option value="1051200"$wbsel->{1051200} >2 years<option value="1576800"$wbsel->{1576800} >3 years<option value="2102400"$wbsel->{2102400}>4 years<option value="2628000"$wbsel->{2628000}>5 years<option value="3153600"$wbsel->{3153600}>6 years</select>
			|;
		$wayfront = qq|
			<b>To:</b> <select name="wayfront" size=1
><option value="0" $wfsel->{0}>now<option value="60"$wfsel->{60} >1 hour<option value="180"$wfsel->{180} >3 hour<option value="360"$wfsel->{360} >6 hours<option value="720"$wfsel->{720} >12 hours<option value="1440"$wfsel->{1440} >1 day<option value="2880"$wfsel->{2880} >2 days<option value="4320"$wfsel->{4320} >3 days<option value="5760"$wfsel->{5760} >4 days<option value="7200"$wfsel->{7200} >5 days<option value="8640"$wfsel->{8640} >6 days<option value="10080"$wfsel->{10080} >1 week<option value="20160"$wfsel->{20160} >2 weeks<option value="40320"$wfsel->{40320} >4 weeks<option value="131040"$wfsel->{131040} >1 quarter<option value="262080"$wfsel->{262080} >6 months<option value="525600"$wfsel->{525600} >1 year<option value="1051200"$wfsel->{1051200} >2 years<option value="1576800"$wfsel->{1576800} >3 years<option value="2102400"$wfsel->{2102400}>4 years<option value="2628000"$wfsel->{2628000}>5 years<option value="3153600"$wfsel->{3153600}>6 years</select>
			|;
		}
	my $res_num = {};
	$res_num->{$args->{count}} = ' SELECTED';
	
	my $page_buttons = qq|<TABLE WIDTH="100%" CELLPADDING=0 CELLSPACING=0 BORDER=0>
				<TR>
				<TD>%%norm_font%%|;
	
	if ($last_page >= 1) {
		$page_buttons .= qq|
			<INPUT TYPE="submit" NAME="last" VALUE="&lt;&lt; Previous Page">|;
	} else {
		$page_buttons .= '&nbsp;';
	}
	
	$page_buttons .= qq|
		%%norm_font_end%%
		</TD>
		<TD ALIGN="right">
		%%norm_font%%|;
	
	if ($next_page) {
		$page_buttons .= qq|
			<INPUT TYPE="submit" NAME="next" VALUE="Next Page &gt;&gt;">|;
	} else {
		$page_buttons .= '&nbsp;';
	}
	
	$page_buttons .= qq|
			%%norm_font_end%%
			</TD>
			</TR>
			</TABLE>|;
			
	my $story_view = sprintf( "<INPUT type=checkbox name=%s value=%s %s> View story summaries",
	              '"story_view"', '"long"', 
	              $S->{CGI}->param('story_view') ? 'CHECKED' : '' );
	# bluh.
	$story_view = '' if ($S->{UI}->{VARS}->{use_pysearch});
	my $search_archive = '';
	
	#if ($S->{HAVE_ARCHIVE} && ($S->{UI}->{VARS}->{story_archive_age} > 0)) {
	#	$search_archive = sprintf( "<INPUT type=\"checkbox\" name=%s value=%s %s> Search Archive",
	#		'"search_archive"', '"yes"', $S->{CGI}->param('search_archive') ? 'CHECKED' : '');
	#}

	my $hidden_view = '';
	
	if ($S->{TRUSTLEV} == 2 || $S->have_perm('super_mojo')) {
		$hidden_view = sprintf( "<INPUT type=\"checkbox\" name=%s value=%s %s> View Hidden Comments",
	              '"hidden_comments"', '"show"',
				  $S->{CGI}->param('hidden_comments') ? 'CHECKED' : '' );
	}

       foreach my $key (qw(offset count string)) {
               $args->{$key} = $S->filter_subject($args->{$key});
       }
				  
	my $secin = "<b>In:</b> " if !$S->{UI}->{VARS}->{use_pysearch};
	my $fresults = (!$S->{UI}->{VARS}->{use_pysearch} || ($S->{UI}->{VARS}->{use_pysearch} && ($args->{type} ne 'story' && $args->{type} ne 'diary' && $args->{type} ne 'both'))) ? "<TD>%%norm_font%%Found $disp_count results.<P>" : '';

	$args->{string} =~ s/"/&quot;/g;
	my $commby;
	#if ($S->cgi->param('search_archive')){
	#	$commby = qq|<p><strong>NOTE:</strong> Searching on comments by a user that are in the archive now uses the new search engine. By default, it searches a period of time between 4 weeks ago and 2 weeks ago. If you would like to search a different range of time, adjust the 'To' and 'From' menu options accordingly.</p>|;
	#	}
	if ($args->{type} eq 'comment_by'){
		$commby = qq|<p><strong>NOTE:</strong> Searching for comments by a user defaults to a period from one week ago to now. To search for comments further in the past, adjust the From: and To: fields accordingly.</p>|;
		}
	my $form = qq|
		
			%%norm_font%% 
			<blockquote>
			<form name="Search" action="%%rootdir%%/search" method="get">
			<input type="hidden" name="offset" value="$args->{offset}" />
			<input type="hidden" name="old_count" value="$args->{count}" />
			<p><b>Search:</b> &nbsp;&nbsp;<input type="text" name="string" value="$args->{string}" size=42 /> <a href="/special/quicktips">Quick Search Tips</a></p>
			<p><b>Find:</b> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$search_type_select 
			$secin $topic_select $section_select
			&nbsp;$sortby &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<input type="submit" name="search" value="Search" />$phrasebox </p>
			<p><b>Results:</b> 
			<select name="count" size=1>
			<option value="10"$res_num->{10}>10
			<option value="20"$res_num->{20}>20
			<option value="30"$res_num->{30}>30
			<option value="40"$res_num->{40}>40
			<option value="50"$res_num->{50}>50
			</select>  
			&nbsp;$wayback $wayfront
			    $story_view</p><p>
			$hidden_view
			</p>
			$relevance_radio
			<p><a href="/special/searchhelp">How does the search work?</a>  <i>* Comment Search Sorting Only</i></p>
			$commby
			</blockquote>
			%%norm_font_end%%

			$fresults
			$results
			%%norm_font_end%%
	<br />	
		<TR>
			<TD ALIGN="center">%%norm_font%%
			$page_buttons
			%%norm_font_end%%
			</FORM>
			</TD>
		</TR>
		</TABLE>|;
	
	return $form;
}


=pod

=over 4

=item *
search_type_select($type);

search_type_select() generates the select box for the type of search to perform.  $type is an optional
parameter specifying the default search type.  If no $type argument is given, it defaults to 'story';

=back

=cut

sub search_type_select {
	my $S = shift;
	my $type = shift || 'story';
		
	my $form = qq|
		<SELECT NAME="type" SIZE=1>
	|;
	
	my %diary = ( (!$S->{UI}->{VARS}->{hide_diary_search}) ? 
					("diary" => 'Diaries', "diary_by" => 'Diaries By') :
					()
				);
	
	my %types = (	"story"		=> 'Stories', 
			"user"		=> 'Users',
			"comment"	=> 'Comments', 
			"author"	=> 'Authors',
			"comment_by"	=> 'Comments By',
			"polls"		=> 'Polls',
			%diary
				 );
	$types{"both"} = "Stories and Diaries" if $S->{UI}->{VARS}->{use_pysearch};

	foreach my $t (sort keys %types) {
		my $sel = ($type eq $t) ? ' SELECTED' : '';
		$form .= qq|
			<OPTION VALUE="$t"$sel>$types{$t}|;
	}
	
	$form .= qq|
		</SELECT>|;
	
	return $form;
}


=pod

=over 4

=item *
search_topic_select($topic);

Same as search_type_select(), this generates the select box for the topic to search.  If no $topic argument
is given, it defaults to All Topics being selected

=back

=cut

sub search_topic_select	{
	my $S = shift;
	my $topic = shift;
	
	my $form = qq|
		<SELECT NAME="topic" SIZE=1>
		<OPTION VALUE="">All Topics|;
		
	my $selected = '';
	foreach my $t (sort keys %{$S->{TOPIC_DATA}}) {
		next if ($t eq 'all' or $t eq 'diary');
		if ($topic eq $t) {
			$selected = ' SELECTED';
		} else {
			$selected = '';
		}
		$form .= qq|
		<OPTION VALUE="$t"$selected>$S->{TOPIC_DATA}->{$t}->{alttext}|;
	}
	$form .= qq|
		</SELECT>|;
	
	return $form;
}

sub search_section_select {
	my $S = shift;
	my $section = shift;
	
	my $form = qq|
		<select name="section" size="1">
		<OPTION VALUE="">All Sections|;

	my $list = $S->_make_section_optionlist('', 'allowed');
	
	$list =~ s/<OPTION VALUE="$section">/<OPTION VALUE="$section" SELECTED>/;
	
	$form .= qq{
		$list
		</SELECT>};
		
	return $form;
}

=pod

=over 4

=item *
search_relevance_radio($orderBy);

search_relevance_radio generates the radio buttons that determine sort order when using FULLTEXT
indexes. MySQL Version 3.23.23 and beyond (as well as various other DBs) support FULLTEXT indexes.
Because some Scoop users may be using a DB/version that does not support this functionality, it is
only active if the administrator sets the Scoop variable 'use_fulltext_indexes' to '1'. FULLTEXT
indexes allow search results scored and sorted by relevance based on the semantic value of the search
terms. As such, the most frequently used words are completely ignored and less frequently used words
are assigned progresively higher values when scoring search results. When this functionality is
turned on users are given the option to sort by date.

Before turning on this functionality be sure to create the two required FULLTEXT indexes:
alter table stories add FULLTEXT storysearch_idx (title,introtext,bodytext)
alter table comments add FULLTEXT commentsearch_idx (subject,comment)


=back

=cut

sub search_relevance_radio {
	my $S = shift;
	my $orderby = shift || 'date';
	my $form = qq|<b>Sort Results By:</b>
		<input type="radio" name="orderby" value="relevance"> Relevance
		&nbsp;&nbsp;&nbsp;&nbsp;
		<input type="radio" name="orderby" value="date"> Date<br />|;
	$form =~ s/value="$orderby">/value="$orderby" CHECKED>/;
	return $form;
}

sub _determine_search_q {
	my $S = shift;
	my $args = shift;
	my $query = {};

	# keep people honest :)
	# following 4 are for > and <
	$args->{string} =~ s/>/&gt;/g; 
	$args->{string} =~ s/</&lt;/g; 
	$args->{string} =~ s/%3e/&gt;/g;
	$args->{string} =~ s/%3c/&lt;/g;

	# these 2 are for "
	$args->{string} =~ s/%22/&quot;/g;
	$args->{string} =~ s/"/&quot;/g;
	
	#remove double % signs
	$args->{string} =~ s/%%//g;

	# used for joining stories to users, as when looking in the archive, the
	# users table is in a different database
	my $db_name;
	$db_name  = $S->{CONFIG}->{db_name} . ".users" if (lc($S->{CONFIG}->{DBtype}) eq "mysql");
	$db_name = $S->{UI}->{VARS}->{db_name_search} . ".users" if($args->{use_seperate_search});
	$db_name  = "users" if (!(lc($S->{CONFIG}->{DBType}) eq "mysql"));


	# get sql to not list the stories that are in sections they can't read
	my $excl_sect_sql = ' AND ' . $S->get_disallowed_sect_sql('norm_read_stories');
	$excl_sect_sql = '' if( $excl_sect_sql eq ' AND ' );

	if ($args->{type} eq 'user') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% User';
		$query->{WHAT} = '*';
		$query->{FROM} = 'users';
		if ($args->{string}) {
			$query->{WHERE} = qq|nickname LIKE '%$args->{string}%'|;
			if ($S->have_perm('edit_user')) {
				$query->{WHERE} .= qq| OR realemail LIKE '%$args->{string}%' OR origemail LIKE '%$args->{string}%'|;
			}
		}
		$query->{ORDER_BY} = 'nickname asc';

	} elsif ($args->{type} eq 'comment') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Comments';
		my $date_format = $S->date_format('c1.date', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{WHAT} = (!$args->{hidden_comments}) ? qq|c1.*, $date_format AS ftime, COUNT(c2.pid) AS replies| : qq|c1.*, $date_format AS ftime|;
		if($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{string})
		{
			$query->{WHAT} .= lc($S->{CONFIG}->{DBType}) eq "mysql" ? 
				qq|, MATCH(c1.subject,c1.comment) AGAINST('$args->{string}') as rank|
				: qq|, 1 as rank|
		}
		$query->{FROM} = (!$args->{hidden_comments}) ? 'comments AS c1 LEFT JOIN comments AS c2 ON c1.cid=c2.pid AND c1.story_id=c2.story_id' : 'comments as c1';
		if ($args->{string}) {
			if($S->{UI}->{VARS}->{use_fulltext_indexes} && !$args->{phrase} && lc($S->{CONFIG}->{DBType}) eq "mysql" ){
				$query->{WHERE} = qq| MATCH(c1.subject,c1.comment) AGAINST('$args->{string}')|;
			} else{
				$query->{WHERE} = qq|(c1.comment LIKE '%$args->{string}%' OR c1.subject LIKE '%$args->{string}%')|;
			}
		}
		$query->{WHERE} .= ($query->{WHERE}) ? ' AND ' : '';
		if ($args->{hidden_comments} && (($S->{TRUSTLEV} == 2) || $S->have_perm('super_mojo'))) {
			$query->{WHERE} .= qq|c1.points < 1|;
		} else {
			$query->{WHERE} .= qq|(c1.points >= 1 OR c1.points IS NULL)|;
		}
		
		# hide comments to stories in the queue unless the user can moderate
		if (!$S->have_perm('moderate') || $S->{UI}->{VARS}->{hide_disabled_comments}) {
			$query->{FROM} .= ' LEFT JOIN stories AS s ON c1.story_id=s.id';
			if(!$S->have_perm('moderate')){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.displaystatus > -2';
			}
			if($S->{UI}->{VARS}->{hide_disabled_comments}){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.commentstatus > -1';
			}
		}

		# MySQL needs the group by for count(pid) to work, Postgres doesn't work with 
		# the group by unless you group _everything_ that isn't part of an aggregate.
		$query->{GROUP_BY} = 'c1.story_id,c1.id' if(lc($S->{CONFIG}->{DBType}) eq "mysql");
		$query->{GROUP_BY} = 'c1.sid,c1.cid,c1.subject,c1.date' if(!(lc($S->{CONFIG}->{DBType}) eq "mysql"));

		unless($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{orderby} eq 'relevance') {
			$query->{ORDER_BY} = 'c1.date desc';
		} else {
			$query->{ORDER_BY} = 'rank desc';
		}

	} elsif ($args->{type} eq 'comment_by') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Comments By';
		my $date_format = $S->date_format('c1.date', 'short');
		my $uid = '';
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$uid = $args->{uid};
		$uid = $S->get_uid_from_nick($args->{string}) unless defined($uid);
		$uid = 'NULL' unless defined($uid);
		
		$query->{WHAT} = qq|c1.*, COUNT(c2.pid) AS replies, $date_format AS ftime|;
		$query->{FROM} = 'comments AS c1 LEFT JOIN comments AS c2 ON c1.cid=c2.pid AND c1.sid=c2.sid';
		$query->{WHERE} = qq|(c1.uid = $uid) AND |;
		$query->{GROUP_BY} = 'c1.date DESC';
		if ($args->{hidden_comments} && (($S->{TRUSTLEV} == 2) || $S->have_perm('super_mojo'))) {
			$query->{WHERE} .= qq|(c1.points < 1)|;
		} else {
			$query->{WHERE} .= qq|(c1.points >= 1 OR c1.points IS NULL)|;
		}

		if (!$S->have_perm('moderate') || $S->{UI}->{VARS}->{hide_disabled_comments}) {
			$query->{FROM} .= ' LEFT JOIN stories AS s ON c1.sid=s.sid';
			if(!$S->have_perm('moderate')){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.displaystatus > -2';
			}
			if($S->{UI}->{VARS}->{hide_disabled_comments}){
				$query->{WHERE} .= ' AND ' if $query->{WHERE};
				$query->{WHERE} .= 's.commentstatus > -1';
			}
		}
		$query->{ORDER_BY} = ($args->{orderby} eq 'relevance')?'c2.date DESC':'c1.date DESC';

	} elsif ($args->{type} eq 'author') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Stories By';
		my $date_format = $S->date_format('time', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{FROM} = "stories s LEFT JOIN $db_name u ON s.aid = u.uid";
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;

		$query->{WHERE} = qq|displaystatus >= 0  AND section != 'Diary' $excl_sect_sql|;
		
		if ($args->{string}) {
			my $uid = $S->get_uid_from_nick($args->{string});
			my $q_uid = $S->{DBH}->quote($uid);
			$query->{WHERE} .= qq| AND aid = $q_uid|;
		} 

		if ($args->{topic}) {
			$query->{WHERE} .= ($query->{WHERE}) ? ' AND ' : '';
			$query->{WHERE} .= qq|tid = '$args->{topic}'|;
		}

		if ($args->{section}) {
			$query->{WHERE} .= ($query->{WHERE}) ? ' AND ' : '';
			$query->{WHERE} .= qq|section = '$args->{section}'|;
		}

		$query->{ORDER_BY} = 'time desc';

	} elsif ($args->{type} eq 'diary_by') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Diaries By';
		my $date_format = $S->date_format('time', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{FROM} = "stories s LEFT JOIN $db_name u ON s.aid = u.uid";
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;
	
		$query->{WHERE} = qq|displaystatus >= 0 AND section = 'Diary' $excl_sect_sql|;

		if ($args->{string}) {
			my $uid = $S->get_uid_from_nick($args->{string});
			my $q_uid = $S->{DBH}->quote($uid);
			$query->{WHERE} .= qq| AND aid = $q_uid|;
		}
		
		if ($args->{topic}) {
			$query->{WHERE} .= qq| AND tid = '$args->{topic}'|;
		}
		
		$query->{ORDER_BY} = 'time desc';

	} elsif ($args->{type} eq 'diary') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Diaries';
		my $date_format = $S->date_format('time', 'short');
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;
		$query->{FROM} = "stories s LEFT JOIN $db_name u ON s.aid = u.uid";
		if($S->{UI}->{VARS}->{use_fulltext_indexes} && !$args->{phrase} && $args->{string}){
			$query->{WHERE} = qq|displaystatus >= 0 and section = 'Diary' and  MATCH(title,introtext,bodytext) AGAINST('$args->{string}') $excl_sect_sql|;
		} else{
			$query->{WHERE} = qq|displaystatus >= 0 and section = 'Diary' and (introtext LIKE '%$args->{string}%' OR bodytext LIKE '%$args->{string}%' OR title LIKE '%$args->{string}%') $excl_sect_sql|;
##			$query->{GROUP_BY} = qq|sid|;
		}
		# I'm ready to try most anything
		$query->{WHERE} = qq|displaystatus >= 0 and section = 'Diary'| if(!$args->{string});
		$query->{ORDER_BY} = 'time desc' unless($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{orderby} eq 'relevance');
	} elsif ($args->{type} eq 'polls') {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Polls';
		my $date_format = $S->date_format('post_date', 'short');
		$query->{WHAT} = qq|*, $date_format AS ftime|;
		$query->{FROM} = 'pollquestions,pollanswers';
		$query->{WHERE} = qq|pollquestions.qid = pollanswers.qid AND ( pollquestions.question LIKE '%$args->{string}%' OR pollanswers.answer LIKE '%$args->{string}%' ) |;
                $query->{GROUP_BY} = qq|pollquestions.qid|;
		$query->{ORDER_BY} = 'pollquestions.post_date desc';

	} else {
		$S->{UI}->{BLOCKS}->{subtitle} .= ' %%bars%% Stories';
		my $date_format = $S->date_format('time', 'short');
		my $search_str = $args->{string}; $search_str =~ s/["'%]//g;
		
		$query->{ARCHIVE} = ($args->{search_archive} ? 1 : 0);
		$query->{WHAT} = qq|*, $date_format AS ftime, u.nickname AS nick|;
		if($S->{UI}->{VARS}->{use_fulltext_indexes} && $search_str)
		{
		$query->{WHAT} .= lc($S->{CONFIG}->{DBType}) eq "mysql" ? 
			qq|, MATCH(title,introtext,bodytext) AGAINST('$search_str') as rank|
			: qq|, 1 as rank|
		}
		$query->{FROM} = "stories s LEFT JOIN $db_name u ON s.aid = u.uid";
		
		my $ad_section_excl;
		if ($S->{UI}->{VARS}->{use_ads} && $S->{UI}->{VARS}->{ad_story_section}) {
			$ad_section_excl = qq|AND section != '$S->{UI}->{VARS}->{ad_story_section}'|;
		}
		
		if($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{string} && !$args->{phrase} && lc($S->{CONFIG}->{DBType}) eq "mysql"){
			$query->{WHERE} = qq|displaystatus >= 0 AND MATCH(title,introtext,bodytext) AGAINST('$search_str') AND section != 'Diary' $ad_section_excl $excl_sect_sql|;
		} else{
			$query->{WHERE} = qq|displaystatus >= 0 AND (introtext LIKE '%$search_str%' OR bodytext LIKE '%$search_str%' OR title LIKE '%$search_str%') AND section != 'Diary' $ad_section_excl $excl_sect_sql|;
		}

		if($S->{UI}->{VARS}->{use_fulltext_indexes} && $args->{orderby} eq 'relevance' ) {
			$query->{ORDER_BY} = 'rank desc';
		} else {
			$query->{ORDER_BY} = 'time desc';
		}

		if ($args->{topic}) {
			$query->{WHERE} .= qq| AND tid = '$args->{topic}'|;
		}
		if ($args->{section}) {
			$query->{WHERE} .= qq| AND section = '$args->{section}'|;
		}
	}

	return $query;
}	

sub _format_search {
	my $S 		= shift;
	my $args 	= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	my $page;
	my $real_count = -1;
	
	if ($args->{type} eq 'user') {
		$page = $S->_format_user_search($sth, $i, $stop);
	} elsif ($args->{type} eq 'comment' || $args->{type} eq 'comment_by') {
		($page, $real_count) = $S->_format_comment_search($sth, $i, $stop, $args->{type});
	} elsif ($args->{type} eq 'polls' ) {
		$page = $S->_format_polls_search($sth, $i, $stop);
	} else {
		$page = $S->_format_story_search($sth, $i, $stop, $args->{type});
	}
	
	return ($page, $real_count);
}

sub _format_story_search {
	my $S 		= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	my $type    = shift;
	my $list;
	
	
	while ((my $story = $sth->fetchrow_hashref) && ($i <= $stop)) 
	{
	    my $topic = {};
		my $comments = $S->_commentcount($story->{sid});
		$story->{commentcount} = $comments;
		
	    if ($story->{tid}) {
			$topic = $S->get_topic($story->{tid});
	    }
		
		$topic->{alttext} = 'All Topics' unless $topic->{alttext};
	   
		my $urltid = $S->urlify($story->{tid});
		my $tid_link = qq|search?topic=$urltid|;
		$tid_link .= qq|;type=diary_by| if ($type eq 'diary') || ($type eq '$diary_by');
		
		my $section_link = qq|section/$story->{section}|;
		
	    if( $S->{CGI}->param('story_view') ne "long" ) {
			my $story_nick = $S->get_nick_from_uid($story->{aid});
			$list .= qq|
		    	<P>
				<B>$i. <A HREF="%%rootdir%%/story/$story->{sid}">$story->{title}</A></B>&nbsp; 
				(<a href="%%rootdir%%/$section_link">$S->{SECTION_DATA}->{$story->{section}}->{title}</a>, <A HREF="%%rootdir%%/$tid_link">$topic->{alttext}</A>)<br />
				posted by $story_nick on $story->{ftime}|;

			# don't display comment count if they aren't supposed to know about it
			unless( $S->have_section_perm( 'hide_read_comments', $story->{section} ) ) {
				my $show = $S->{UI}->{VARS}->{show_new_comments};
				my $num_new = 'no';
				$num_new = $S->new_comments_since_last_seen($story->{sid}) if ($show eq "all" && $S->{UID} != -1);
				my $end_s = ($story->{commentcount} == 1) ? '' : 's';
				
				$list .= qq|<br />$comments comment|.$end_s;
				if ($num_new ne 'no') {
					$list .= qq| (<b>$num_new</b> new)|;
				}
			} else {
				$list .= qq|<br />|;
			}

			if( ($type eq 'story' || $type eq 'diary')		&&
				$S->{UI}->{VARS}->{use_fulltext_indexes}	&&
				($S->cgi->param('phrase') ne 'true')		) {
				$list .= qq| <br /> Rank: <b>| . sprintf( "%.2f", $story->{rank} ) . "</b>";
			}

	    } else {
			$list .= $S->old_story_summary( $story, 1 );
	    }
	    $i++;
	}
	return $list;
}


sub _format_user_search {
	my $S 		= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	
	my $list;
	while ((my $user = $sth->fetchrow_hashref) && ($i <= $stop)) {
		$list .= qq|
			<P>
			<B><A HREF="%%rootdir%%/user/uid:$user->{uid}">$user->{nickname}</A></B>|;
		
		if ($S->have_perm('edit_user')) {
			$list .= qq| [ <A HREF="%%rootdir%%/user/uid:$user->{uid}/edit">Edit</A> ]|;
		}
		
	}
	
	return $list;
}

sub _format_comment_search {
	my $S 		= shift;
	my $sth 	= shift;
	my $i 		= shift;
	my $stop 	= shift;
	my $argtype = shift;
	
	my ($title, $nick, $num_rate, $list);
	my $counted = 0;
	
	while ((my $comment = $sth->fetchrow_hashref) && ($i <= $stop)) {

		# don't display comments from stories that aren't posted
		next if ($S->{UI}->{VARS}->{hide_unposted_comments} && ($S->_check_story_mode($comment->{sid}) < 0));

		# also don't display if they don't have perms to read it
		next unless($S->_does_poll_exist($comment->{sid})	||
					$S->have_section_perm('norm_read_comments',$S->_get_story_section( $comment->{sid} ))
					);

		$num_rate = ($comment->{recrate} + $comment->{trollrate}) || $comment->{lastmod};
		$num_rate = 0 if ($num_rate == '-1');
		
		my $score = $comment->{points} || 'none';
		
		if( $S->_does_poll_exist($comment->{sid}) ) {
			$title = $S->get_poll_hash($comment->{sid})->{question};
		} else {
			$title = $S->_get_story_title($comment->{sid});
		}

		$nick = $S->get_nick($comment->{uid});
		
		# Edited to go to the cid link. this is more efficient for page loading, usually.
		my $replylist;
		unless ($S->cgi->param('hidden_comments')){
			$replylist = "Replies: <B>$comment->{replies}</B>";
			}
		$list .= qq|
			<B>$i) <A HREF="%%rootdir%%/comments/$comment->{sid}/$comment->{cid}#c$comment->{cid}">$comment->{subject}</A></B> [<A HREF="%%rootdir%%/comments/$comment->{sid}/$comment->{cid}?mode=alone;showrate=1#c$comment->{cid}">$score / $num_rate</A>] $replylist
			<br />posted by <A HREF="%%rootdir%%/user/uid:$comment->{uid}">$nick</A> on $comment->{ftime}|;

		# if its a poll it needs a different link to display it
		if( $S->_does_poll_exist($comment->{sid}) ) {
			$list .= qq|<br />attached to <A HREF="%%rootdir%%/view_poll/$comment->{sid}">$title</A>|;
		} elsif( !$S->have_section_perm('hide_read_stories', $S->_get_story_section($comment->{sid})) ) {
			$list .= qq|<br />attached to <A HREF="%%rootdir%%/story/$comment->{sid}">$title</A>|;
		}

		$list .= qq|<P>|;

		$i++;
		$counted++;
	}
	
	return ($list, $counted);
}


sub _format_polls_search {
	my $S       = shift;
	my $sth     = shift;
	my $i       = shift;
	my $stop    = shift;

	my ($qid, $question, $list, $post_date, $vote);

	while( (my $poll = $sth->fetchrow_hashref) && ($i <= $stop) ) {
		$qid = $poll->{qid};
		$question = $poll->{question};
		$post_date = $poll->{post_date};

		if( $S->_can_vote( $qid ) ) {
			$vote = qq|\| <a href="%%rootdir%%/?op=poll_vote;qid=$qid">Vote</a>|;
		} 
	
		$list .= qq|<P>$i) "$question" [ <A HREF="%%rootdir%%/poll/$qid">View</A> $vote ]<br />&nbsp;&nbsp;&nbsp;&nbsp; posted on $poll->{ftime}</P>|;
		
		# to make sure we don't get the value sticking around for later polls
		$vote = '';

		$i++;
	}

	return $list;
}

1;	
