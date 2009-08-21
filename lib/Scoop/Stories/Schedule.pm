package Scoop;
use strict;
my $DEBUG = 0;


# Schedule a story for posting

sub schedule_post {
	my $S = shift;
	my $params = shift; # %params in save story is a normal hash, so we
	 		    # get a ref. Huzzah.
	return undef unless $S->have_perm('story_sched');
	
	# I'm a little leery of this, but it should be OK. Now, if you try
	# scheduling something to publish to the queue *or* as a draft, it
	# intercepts and sets the displaystatus to 0.
	my $disp = ($params->{displaystatus} < -3) ? 0 : $params->{displaystatus};
	my $id = $params->{id} || $S->get_story_id_from_sid($params->{sid});
	# Figure out when we're posting this.
	my $ht = $params->{scheduleTime};
	my $hd = $params->{scheduleDate};
	# this is easy, at least
	my @darr = split '/', $hd;
	# little gimpy, but works
	my $mer = substr($ht, -2, 2);
	substr($ht, -2, 2) = '';
	my @tarr = split /:/, $ht;
	# change hour to 24 hour time
	$tarr[0] = ($tarr[0] == 12) ? 0 : $tarr[0];
	$tarr[0] += ($mer eq 'PM') ? 12 : 0;
	# Convert time for scheduling
	my ($y, $mo, $d, $h, $m, $s) = $S->time_to_utc_array($darr[2], $darr[0], $darr[1], $tarr[0], $tarr[1], 00);
	($y, $mo, $d, $h, $m, $s) = $S->time_localize_array($y, $mo, $d, $h, $m, $s, 0, $S->{UI}->{VARS}->{time_zone});
	my $timestr = "$y-$mo-$d $h:$m:$s";
	my $qtimestr = $S->dbh->quote($timestr);

	# Let's wrap this in an eval and transaction to test for success
	unless($S->db_start_transaction()){
		warn "Transaction failed to start!\n";
		return (0, "Transaction in scheduling failed to start\n");
		}
	eval {
		$S->db_insert({
			INTO => 'storysched',
			COLS => 'id, displaystatus, posttime',
			VALUES => "$id, $disp, $qtimestr",
			DUPLICATE => "displaystatus = $disp, posttime = $qtimestr"
			});
		};
	unless($@){
		$S->db_commit();
		$params->{displaystatus} = $params->{olddsp}; # keep it where
							      # it is.
		return (1, "Story scheduled for posting at $timestr $S->{UI}->{VARS}->{time_zone}");
		}
	else {
		$S->db_rollback();
		return (undef, "Scheduling failed, rolling back. Error message was: $@\n");
		}
	}

# much like save_story() in AdminStories.pm, but for publishing a previously
# scheduled post. Has to be separate because of the lack of cgi params.

sub sched_post_story {
	my $S = shift;
	my $id = shift;

	my ($rv, $sth) = $S->db_select({
		WHAT => 'id, posttime, displaystatus',
		FROM => 'storysched',
		WHERE => "id = $id"
		});
	my $sched = $sth->fetchrow_hashref();
	$sth->finish;
	my $sd = $S->story_basic_data_arr($id);
	# How old are we?
	($rv, $sth) = $S->db_select({
		WHAT => 'TO_DAYS(NOW()) - TO_DAYS(time)',
                FROM => 'stories',
                WHERE => "id = $id"
		});
	my $age = $sth->fetchrow();
	$sth->finish;
	my $sid = $sd->[0];
	if ($age != 0){
		my $upsid = $S->make_new_sid();
		my $nk;
		($sid, $nk) = $S->update_sid($sid, $upsid);
		warn "Sid: $sid Msg: $nk\n";
		return 0 if(!$sid);
		}
	warn "here?\n";
	# Update displaystatus, clear caches, and all that. Then we should be
	# good.
	$sched->{posttime} = $S->dbh->quote($sched->{posttime});
	$sched->{displaystatus} = $S->dbh->quote($sched->{displaystatus});
	$S->db_update({
		WHAT => 'stories',
		SET => "displaystatus = $sched->{displaystatus}, time = NOW()",
		WHERE => "id = $id"
		});
	$S->db_update({
		WHAT => 'storysched',
		SET => 'pub = 1',
		WHERE => "id = $id"
		});
	$S->story_cache->del($sid);
        $S->story_cache->asd_del($sid);
        $S->story_cache->del_arr($sid);
        $S->story_cache->asd_del_arr($sid);
        delete $S->{STORY_CACHE}->{$sid};
        delete $S->{STORY_CACHE_ARR}->{$sid};
                for (my $i = 1; $i < 5; $i++){
                        $S->cache->remove("main-${i}_15");
                        }

	return 1;
	}

sub sched_pub_list {
	my $S = shift;
	my ($rv, $sth) = $S->db_select({
		WHAT => 'storysched.id',
		FROM => 'storysched left join stories on storysched.id = stories.id',
		WHERE => 'stories.displaystatus <= -4 and pub = 0 and posttime < NOW()'
		});
	my $arr = ();
	while (my $s = $sth->fetchrow()){
		push @{$arr}, $s;
		warn "Fetched $s\n";
		}
	$sth->finish;
	return $arr;
	}

# cron job to update stories as needed
sub cron_sched {
	my $S = shift;
	my $list = $S->sched_pub_list();
	warn "Trying to get through here...\n";
	my $tt = localtime();
	foreach my $s (@{$list}){
		warn "Cockbite fuck: $s $tt\n";
		$S->sched_post_story($s);
		}
	return 1;
	}

# convert scheduled time to the format the ajax part of it wants to use
sub sched_time_format {
	my $S = shift;
	my $id = shift;
	$id = $S->dbh->quote($id);
	# hmm?
	my ($adjust, $z) = $S->time_localize("posttime");
	my ($rv, $sth) = $S->db_select({
		WHAT => qq|date_format($adjust, "%m/%d/%Y %h:%i%p") as p|,
		FROM => 'storysched',
		WHERE => "id = $id"
		});
	my $dtstr = $sth->fetchrow;
	$sth->finish;
	return $dtstr;
	}

# deschedule a post
sub deschedule_post {
	my $S = shift;
	my $params = shift;
	my $id = $params->{id} || $S->get_story_id_from_sid($params->{sid});
	# No fuss, no muss, all things considered
	$S->db_delete({
		FROM => 'storysched',
		WHERE => "id = $id"
		});
	return;
	}

sub scheduled_list {
	my $S = shift;
	# what do we have?
	my $date_format = $S->date_format('posttime');
	my $content;
	my ($rv, $sth) = $S->db_select({
                WHAT => "storysched.id, sid, title, aid, nickname, $date_format as f_date",
                FROM => 'storysched left join stories on storysched.id = stories.id left join users on stories.aid = users.uid',
                WHERE => 'stories.displaystatus <= -4 and pub = 0',
		ORDER_BY => 'posttime'
                });
	$content .= "<div><ol>";
	while (my $s = $sth->fetchrow_hashref()){
		my $modo = $S->moduloze($s->{id});
		$content .= qq|<li><a href="/story/$s->{sid}/$modo/$s->{id}">$s->{title}</a> by <a href="/user/$s->{nickname}">$s->{nickname}</a> scheduled for $s->{f_date}</li>|;
		}
	$sth->finish;
	$content .= "</ol></div>";
	return $content;
	}

sub is_scheduled {
	my $S = shift;
	my $id = shift;
	my ($rv, $sth) = $S->db_select({
		WHAT => 'count(*)',
		FROM => 'storysched',
		WHERE => "id = $id AND pub = 0"
		});
	return $sth->fetchrow();
	}

1;
