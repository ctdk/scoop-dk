package Scoop;
use strict;
my $DEBUG = 0;

# Implementation of story_data and story_basic_data to use fetchrow_arrayref
# instead of fetchrow_hashref, to experiment with improving speed and memory
# usage with a tradeoff on ease of use.

# The big changes here are to specify what columns we're fetching from stories
# rather than using s.*. This way we won't break anything if columns are added
# to the stories table, but it does mean that the columns will have to be added
# manually.

# A key for array values
# sid 0
# tid 1
# aid 2
# title 3
# dept 4
# time 5
# introtext 6
# bodytext 7
# writestatus 8
# hits 9
# section 10
# displaystatus 11
# commentstatus 12
# totalvotes 13
# score 14
# rating 15
# attached_poll 16
# sent_email 17
# edit_category 18
# to_archive 19
# author_intro 20 
# author_body 21
# author_title 22 
# goatse_draft 23
# is_quick 24
# dsid 25
# id 26
# hotlisted 27 ### basic data has "ftime" here, and ends here
# lastseen 28
# highest_idx 29
# nick 30
# ftime 31
# comments 32
# w3ctime 33
# gmttime 34
# archive (if set) 35

sub story_data_arr {
	my $S = shift;
	my $sids = shift;

	my $return_stories;
	my $q_uid = $S->dbh->quote($S->{UID});

	# are we looking for sids, or ids? We'll examine the first element of
	# the arrayref to find out. If it matches a non-digit character, $flag
	# is set to 0, but if it doesn't, it's set to one
	my $flag = ($sids->[0] =~ /\D/) ? 0 : 1;
	my $fetching = ($flag) ? 's.id' : 's.sid';
	my $f = ($flag) ? 26 : 0;

	warn "(story_data) starting..." if $DEBUG;
        my $main_db = $S->{CONFIG}->{db_name};
	my $sids_to_fetch;
	
	foreach (@$sids) {
		if($S->{UID} < 0){
                        # stick the anon story cache into STORY_CACHE while
                        # we're looking at it, I guess
                        $S->{STORY_CACHE_ARR}->{$_} ||= $S->story_cache->asd_arr($_);
                        }
		push @$sids_to_fetch,$_ unless ($S->{STORY_CACHE_ARR}->{$_});
	}

	if ( $sids_to_fetch ) {
		warn "(story_data) getting @$sids_to_fetch from database" if $DEBUG;
		my $sids_sql = join(',', map { $S->dbh->quote($_) } (@$sids_to_fetch) );
	
	
		# build the SQL query for those stories not in the cache
		my $date_format = $S->date_format('time');
		my $w3c_format = $S->date_format('time', 'W3C');
		my $gmt_format = $S->date_format('time', 'RSS2');
	
		my ($rv,$sth) = $S->db_select({
			DEBUG => $DEBUG,
			WHAT => "s.sid, s.tid, s.aid, s.title, s.dept, s.time, s.introtext, s.bodytext, s.writestatus, s.hits, s.section, s.displaystatus, s.commentstatus, s.totalvotes, s.score, s.rating, s.attached_poll, s.sent_email, s.edit_category, s.to_archive, s.author_intro, s.author_body, s.author_title, s.goatse_draft, s.is_quick, s.dsid, s.id,v.hotlisted,v.lastseen,v.highest_idx,u.nickname as nick,$date_format as ftime,count(c.cid) as comments, $w3c_format as w3ctime, $gmt_format as gmttime",
			FROM => "stories s LEFT JOIN ${main_db}.users u ON s.aid = u.uid LEFT JOIN ${main_db}.viewed_stories v ON (s.sid = v.sid AND v.uid = $q_uid) LEFT JOIN comments c ON s.id = c.story_id",
			WHERE => "$fetching IN ($sids_sql)",
			GROUP_BY => 's.id',
			FORCE_MASTER => ($S->cgi->param('new')) ? 1 : 0
		});
	
		#while ( my @story = $sth->fetchrow_array() ) {
		my $sss = $sth->fetchall_arrayref();
		foreach my $story (@{$sss}){
			#my $story = \@story;
			# cache them
			#my @s = @{$story};
			delete $S->{STORY_CACHE_ARR}->{$story->[$f]};
                        $S->{STORY_CACHE_ARR}->{$story->[$f]} = $story;
			# for anon, too
			$S->story_cache->asd_arr($story->[$f], $story);
		}
	}

	$sids_to_fetch = ();
	foreach (@$sids) {
		# for some reason, the way that's commented out doesn't seem
		# to be working.
		push @$sids_to_fetch,$_ unless ($S->{STORY_CACHE_ARR}->{$_});
#s ( grep { /^$_$/ } (keys %{$S->{STORY_CACHE}}) );
		# checking to see if we got them all - if not, we look in the archive
	}
	if ( $sids_to_fetch && $S->{HAVE_ARCHIVE} ) {
		warn "(story_data) getting @$sids_to_fetch from archive database" if $DEBUG;
		my $sids_sql = join(',', map { $S->dbh->quote($_) } (@$sids_to_fetch) );
	
	
		# build the SQL query for those stories not in the cache
		my $date_format = $S->date_format('time');
		my $w3c_format = $S->date_format('time', 'W3C');
		my $gmt_format = $S->date_format('time', 'RSS2');
		my $db_name = $S->{CONFIG}->{db_name} . ".users";	
		my ($rv,$sth) = $S->db_select({
			DEBUG => $DEBUG,
			ARCHIVE => 1,
			WHAT => "s.sid, s.tid, s.aid, s.title, s.dept, s.time, s.introtext, s.bodytext, s.writestatus, s.hits, s.section, s.displaystatus, s.commentstatus, s.totalvotes, s.score, s.rating, s.attached_poll, s.sent_email, s.edit_category, s.to_archive, s.author_intro, s.author_body, s.author_title, s.goatse_draft, s.is_quick, s.dsid, s.id, v.hotlisted,v.lastseen,v.highest_idx,u.nickname as nick,$date_format as ftime,count(c.cid) as comments, $w3c_format as w3ctime, $gmt_format as gmttime",
			FROM => "stories s LEFT JOIN $db_name u ON s.aid = u.uid LEFT JOIN ${main_db}.viewed_stories v ON (s.sid = v.sid AND v.uid = $q_uid) LEFT JOIN comments c ON s.sid = c.sid",
			WHERE => "$fetching IN ($sids_sql)",
			GROUP_BY => 's.id'
		});
	
		#while ( my $story = $sth->fetchrow_arrayref() ) {
		my $sarch = $sth->fetchall_arrayref();
		foreach my $story (@{$sarch}){
			# sigh. This would have been handy to leave alone, but
			# we can try just pushing it onto the end
			#$story->{archived} = 1;
			push @{$story}, 1;
			# cache them
			$S->{STORY_CACHE_ARR}->{$story->[$f]} = $story;
			$S->story_cache->asd_arr($story->[$f], $story);
		}
	}

	foreach (@$sids) {
		# assume they were given to us in the correct order
		# method to recover from the story in the cache being deleted
		# while we were getting the story data. Shouldn't happen too
		# much though, only when someone's edited a story while we
		# were loading the page, but better safe that sorry
		push @$return_stories,$S->{STORY_CACHE_ARR}->{$_} if $S->{STORY_CACHE_ARR}->{$_};
		warn "(story_data) returning $_" if $DEBUG;
	}
	if ($DEBUG){
		foreach my $rs (@$return_stories){
			warn "return_stories: $rs\n";
			}
		foreach my $ca (keys %{$S->{STORY_CACHE_ARR}}){
			warn "cache arr: $ca $S->{STORY_CACHE_ARR}->{$ca}->[0]\n";
			}
		}
	return $return_stories;
}
sub story_basic_data_arr {
        my $S = shift;
        my $sid = shift;
	my $flag = ($sid =~ /\D/) ? 0 : 1;
	my $fetching = ($flag) ? 'id' : 'sid';
        # at least now we'll be able to use *some* form of the story_cache,
        # even though we won't be able to use it for everything.
        # Non-personalized data
        if(my $ret = $S->story_cache->get_arr($sid)){
                return $ret;
                }
        # get the info

        # ideally, we'd be able to adjust the time depending on the timezone
        # of the requesting user, so we won't have to be reloading the cache
        # everytime a change is made for multiple timezones
        # first, though, just get it working with having to have the stuff
        # for multiple timezones. The story_cache stuff will at least keep
        # that separate.

        my $date_format = $S->date_format('time');
        my $q_sid = $S->dbh->quote($sid);
        my ($rv, $sth) = $S->db_select({
                ARCHIVE => $S->_check_archivestatus($sid),
                WHAT => "sid, tid, aid, title, dept, time, introtext, bodytext, writestatus, hits, section, displaystatus, commentstatus, totalvotes, score, rating, attached_poll, sent_email, edit_category, to_archive, author_intro, author_body, author_title, goatse_draft, is_quick, dsid, id, $date_format as ftime",
                FROM => 'stories',
                WHERE => "$fetching = $q_sid"
                });
        my $story = $sth->fetchrow_arrayref();
        $sth->finish;
        # store this bitch.
        $S->story_cache->set_arr($sid, $story);
        # and send it back
        return $story;
        }

1;
