package Scoop;
use strict;
my $DEBUG = 0;

sub update_mojo {
	my $S = shift;
	my $update_users = shift;
	
	my($mojo, $count);
	foreach my $uid (keys %{$update_users}) {
		warn "Calculating mojo for user $uid\n" if $DEBUG;
		next unless ($uid > 0);
		($mojo, $count) = $S->calculate_mojo($uid);
		$S->write_mojo($uid, $mojo, $count);
		$S->calc_autoban($uid, $mojo);
	}
	
	return;
}

sub calculate_mojo {
	my $S   = shift;
	my $uid = shift;

	# Fuck it, let's cache it for a bit at least. It'll make massive
	# amounts of rating less painful.
	if (my $mj = $S->cache->fetch("mojo_$uid")){
		# we haz it.
		my ($m, $c) = split /:/, $mj;
		undef $m if ($m eq 'NULL');
		return ($m, $c);
		}

	my $max_days     = $S->{UI}->{VARS}->{mojo_max_days};
	my $max_comments = $S->{UI}->{VARS}->{mojo_max_comments};
	
	my $fetch = {
		WHAT => 'comments.points, comments.lastmod, comments.id, comments.story_id',
		FROM => 'comments',
		WHERE => qq|comments.uid = $uid AND comments.points IS NOT NULL|,
		ORDER_BY => 'comments.id desc',
		LIMIT => qq|$max_comments|,
		DEBUG => 0
	};
	
	if ($S->{UI}->{VARS}->{mojo_ignore_diaries}) {
		$fetch->{WHERE} .= qq| AND stories.section != 'Diary'|;
	}	
	
	#my ($rv, $sth) = $S->db_select( $fetch );
	# Hmph.
	my $qod = qq|(select points, lastmod, id, story_id from comments where uid = $uid and points IS NOT NULL limit 30) union (select points, lastmod, id, story_id from mojoheim where uid = $uid and points IS NOT NULL limit 30) order by id desc limit 30|;
	my $dbh = $S->get_dbh(1);
	my $sth = $dbh->prepare($qod);
	my $rv = $sth->execute;
	my ($sum, $count);
	my $weight = $max_comments;
	my $real_count = 0;
	while (my ($rating, $number, $cid, $sid) = $sth->fetchrow()) {
		$real_count++;
		# For auto set rating, number is -1, so set it here.
		$number = 1 if ($number <= 0);
		$count += ($weight * $number);
		$sum += (($rating * $weight) * $number);
		$weight--;
		warn "\tFrom cid $cid, Story $sid, rating is $rating: \n\tCount: $count, weight: $weight, Sum: $sum Real count: $real_count\n" if $DEBUG;
	}
	$sth->finish();

	# FIXME: lack of archive is scrwing this up
	#if($rv < $max_comments){
	#	$fetch->{ARCHIVE} = 1;
	#	$fetch->{WHERE} .= " and id >= (select id from comments where date > date_sub(now(), interval 30 day) limit 1)";
	#	($rv, $sth) = $S->db_select( $fetch );
	#	while (my ($rating, $number, $cid, $sid) = $sth->fetchrow()) {
	#		$real_count++;
	#		$number = 1 if ($number <= 0);
	#		$count += ($weight * $number);
	#		$sum += (($rating * $weight) * $number);
	#		$weight--;
	#		}
	#	$sth->finish();
	#	}
	
	my $new_mojo = ($sum / $count) unless ($count == 0);
	
	warn "New mojo for user $uid is $new_mojo\n" if $DEBUG;
	# cache it!
	my $mc = ((defined $new_mojo) ? $new_mojo : 'NULL') . ":$real_count";
	$S->cache->store("mojo_$uid", $mc, "+20m");
	return($new_mojo, $real_count);
}

sub write_mojo {
	my $S = shift;
	my ($uid, $mojo, $count) = @_;
	my $set = $S->dbh->quote($mojo);
	unless ($mojo) {
		warn "Mojo is blank. Saving NULL\n" if $DEBUG;
		undef $mojo;
		$set = "NULL";
	}
	
	warn "Saving mojo $mojo for user $uid\n" if $DEBUG;
	my ($rv, $sth) = $S->db_update({
		WHAT => 'users',
		SET  => qq|mojo = $set|,
		WHERE=> qq|uid = $uid|});
	
	$sth->finish();
	
	# Check for trust lev, and set that
	$S->_set_trust_lev($uid, $mojo, $count);
	
	return;
}


sub _set_trust_lev {
	my $S = shift;
	my ($uid, $mojo, $count) = @_;
	
	my $trustlev = 1;
	my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
	# adding age stuff. Defaults to 3 months for now for being able to get
	# TU status.
	#my $udata = $S->user_data($uid);
	my $mtime = $S->{UI}->{VARS}->{tu_min_age};
	$mtime *= 86400;
	my $cmtime = time() - $mtime;
	my ($rv1, $sth1) = $S->db_select({
		WHAT => 'UNIX_TIMESTAMP(creation_time)',
		FROM => 'users',
		WHERE => qq~uid = $uid~
		});
	my $uctime = $sth1->fetchrow;
	$sth1->finish;
	if (($mojo >= $S->{UI}->{VARS}->{mojo_rating_trusted}) &&
		($count >= $S->{UI}->{VARS}->{mojo_min_trusted}) && ($cmtime > $uctime)) {
		warn "User $uid is trusted!\n" if $DEBUG;
		$trustlev = 2;
	} elsif (($mojo <= $hide_thresh) &&
			 ($count >= $S->{UI}->{VARS}->{mojo_min_untrusted})) {
		warn "User $uid is untrusted!\n" if $DEBUG;
		$trustlev = 0;
	}

	my ($rv, $sth) = $S->db_update({
		WHAT => 'users',
		SET => qq|trustlev = $trustlev|,
		WHERE => qq|uid = $uid|,
		DEBUG => 0});
		
	$sth->finish();
	return;

}


1;
