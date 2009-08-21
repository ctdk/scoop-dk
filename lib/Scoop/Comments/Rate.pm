package Scoop;
use strict;
my $DEBUG = 0;

sub _comment_rating_select {
	my $S = shift;
	my $rating = $S->get_comment_option('commentrating');
	
	my ($selected_l, $selected_d, $selected_h);
	
	if ($rating eq 'highest') {
		$selected_h = ' SELECTED';
	} elsif ($rating eq 'lowest') {
		$selected_l = ' SELECTED';
	} elsif ($rating eq 'dontcare') {
		$selected_d = ' SELECTED';
	}
	
	my $select = qq|<SELECT NAME="commentrating" SIZE=1>
		<OPTION VALUE="unrate_highest">Unrated, then Highest
		<OPTION VALUE="highest"$selected_h>Highest Rated First
		<OPTION VALUE="lowest"$selected_l>Lowest Rated First
		<OPTION VALUE="dontcare"$selected_d>Ignore Ratings
		</SELECT>|;
	
	return $select;
}


sub _comment_rating_choice {
	my $S = shift;
	my $comment_rating_choice = $S->get_comment_option('ratingchoice');
	
	my ($sel_no, $sel_hide);
	if ($comment_rating_choice eq 'no') {
		$sel_no = ' SELECTED';
	} 
	if ($comment_rating_choice eq 'hide') {
		$sel_hide = ' SELECTED';
	}
	
	my $select = qq|<SELECT NAME="ratingchoice" SIZE=1>
		<OPTION VALUE="yes">Yes
		<OPTION VALUE="no"$sel_no>No
		<OPTION VALUE="hide"$sel_hide>Hide
		</SELECT>|;
	
	return $select;
}

sub _comment_hiding_choice {
	my $S = shift;
	my $comment_hiding_choice = $S->get_comment_option('hidingchoice');
	
	my ($sel_yes, $sel_ur);
	if ($comment_hiding_choice eq 'yes') {
		$sel_yes = ' SELECTED';
	} 
	if ($comment_hiding_choice eq 'untilrating') {
		$sel_ur = ' SELECTED';
	} 
	
	my $select = qq|<SELECT NAME="hidingchoice" SIZE=1>
		<OPTION VALUE="no">No
		<OPTION VALUE="yes"$sel_yes>Yes
		<OPTION VALUE="untilrating"$sel_ur>Show until I've rated
		</SELECT>|;
	
	return $select;
}

sub _rating_form {
	my $S = shift;
	my $rating = shift;
	my $cid = shift;
	return '' unless ($S->have_perm('comment_rate'));

	my $op = $S->{CGI}->param('op');
	my $dynamic = ($op eq 'dynamic');
	my $dispmode = $S->get_comment_option('commentmode');
	my $tool = $S->{CGI}->param('tool');
	return '' if( $op eq 'comments' && $tool eq 'post' );
	
	my $min = $S->{UI}->{VARS}->{rating_min};
	undef my $sub_min;
	if (($S->{UI}->{VARS}->{use_mojo}) &&
		($S->{TRUSTLEV} == 2 || $S->have_perm('super_mojo'))) {
		my $hide_rating = $S->{UI}->{VARS}->{hide_rating_value};
		$sub_min = ($hide_rating == '') ? ($min - 1) : $hide_rating;
	}
	
	my $max = $S->{UI}->{VARS}->{rating_max};
	
	my @labels = split /,/, $S->{UI}->{VARS}->{rating_labels} if ($S->{UI}->{VARS}->{rating_labels});
	
	# Make sure if we haven't rated that the rating doesn't match any of the num values
	if ($rating eq 'none') {
		$rating = $max + 1;
	}

	my($form,$form_onchange,$form_submit);
	if($dynamic || $dispmode eq 'dthreaded' || $dispmode eq 'dminimal') {
		$form_onchange  = qq| onchange="toggle($cid,0,1,this.value)"|;
		$form_submit    = '';
	} else {
		$form_onchange  = '';
		$form_submit    = qq|<input type="submit" class="rab" name="rate" value="Rate All" />|;
	}
	my ($i, $select, $label);
	my $trool;
	if (defined $sub_min) {
		$select = ($rating == $sub_min) ? ' checked="checked"' : '';
		$label = shift @labels || $sub_min;
		
		# are we in a position to be able to trollrate comments?
		#my $trlchk = $S->trl_check($S->{UID});
		#warn "trldisable would be $trlchk\n";
		my $trldisable = (!$S->trl_chk($S->{UID})) ? 'disabled="disabled" ' : '';
		$trool .= qq|
			<input type="radio" id="t$cid" name="r$cid" value="$sub_min"$select $trldisable/><label for="t$cid">$label</label>|;
	} else {
		shift @labels;
	}
		
	#for ($i = $min; $i <= $max; $i++) {
	#	$select = ($rating == $i) ? ' SELECTED' : '';
	#	
	#	$label = shift @labels || $i;
	#	
	#	$form .= qq|
	#		<OPTION VALUE="$i"$select>$label|;
	#}
	# these days, we just use the highest
	my $toplabel = pop @labels;
	my $buttontype = (defined $sub_min) ? 'radio' : 'checkbox';
	$select = ($rating == $max) ? ' checked="checked"' : '';
	$form .= qq|<input type="$buttontype" id="rc$cid" name="r$cid" value="$max"$select /><label for="rc$cid">$toplabel</label>|;
		
	$form .= qq|$trool
		$form_submit
		|;
	
	return $form;
}			

sub _set_current_ratings {
	my $S = shift;
	my $sid = shift;
	my $uid = shift;
	$S->{CURRENT_RATINGS}->{$sid} = {};
	
	# Get all ratings by this user for this article
	my ($rv, $sth) = $S->db_select({
		DEBUG => 0,
		WHAT => 'cid, rating',
		FROM => 'commentratings',
		WHERE => qq|sid = '$sid' AND uid = $uid|});
	
	while (my ($cid, $rating) = $sth->fetchrow()) {
		$S->{CURRENT_RATINGS}->{$sid}->{$cid} = $rating;
	}
	
	$sth->finish();
	
	return;
}


sub _get_current_rating {
	my $S = shift;
	my ($sid, $cid, $uid) = @_;
	
	unless (defined($S->{CURRENT_RATINGS}->{$sid})) {
		$S->_set_current_ratings($sid, $uid);
	}
	
	my $rating = 'none';
	if (defined($S->{CURRENT_RATINGS}->{$sid}->{$cid})) {
		$rating =  $S->{CURRENT_RATINGS}->{$sid}->{$cid};
	}
	
	return $rating;
}

# This is now an iterator for multi-comment ratings
sub rate_comment {
	my $S = shift;
	my $sid = $S->{CGI}->param('sid');
	my $qid = $S->{CGI}->param('qid');
	
	return undef unless $S->have_perm('comment_rate');
	
	# if its a poll or a story will depend on whether or not $sid or $qid is set.
	# since $sid is used so much below, I use this "test", so that the sid is itself
	# if set, else its the poll qid
	$sid = $sid || $qid;
	
	# Now run through all rating fields.
	my $params = $S->{CGI}->Vars();
	
	my $mojo_update = {};
	foreach my $key (keys %{$params}) {
		next unless ($key =~ /^r\d/);
		#my ($trash, $cid) = split /_/, $key;
		my $cid = $key;
		$cid =~ s/^r//;
		my $rating = $params->{$key};
		
		next if ($rating eq 'none' || $rating !~ /^-{0,1}\d+$/);
		warn "New rating is $rating\n" if $DEBUG;
		my $c_uid = $S->_write_one_rating($sid, $cid, $rating, $S->{REMOTE_IP});
		$mojo_update->{$c_uid} = 1;
	}
	
	# Update mojo of affected users
	if ($S->{UI}->{VARS}->{use_mojo}) {
		$S->update_mojo($mojo_update);
	}
	
	# Mark the story modified in the cache
	unless ($qid) {
		my $time = time();
		my $r = $sid.'_mod';
		$S->cache->stamp_cache($r, $time);
	}
	
	return;
}		


sub _write_one_rating {
	my $S = shift;
	my ($sid, $cid, $rating, $ip) = @_;
	my $sys_rate = shift;

	# Rating range check
	$rating = $S->_verify_rating($rating);
	
	my $uid = $S->{UID};
	my $comm_uid = 0;

	# $test_uid is to make sure people aren't rating their own comments
	# if it matches $S->{UID} return.  else, set $comm_uid to it at the bottom
	my $test_uid = $S->_get_uid_of_comment($sid, $cid);
	
	return unless (defined($test_uid));
	return $comm_uid if ($test_uid == $uid);	
	return $comm_uid unless ($S->_check_rating_perm($sid, $cid));
	return $comm_uid unless $sys_rate;
	#return if ($rating == 0);
	# and return if we've used up our troll ratings
	return if(($rating == 0) && !$S->trl_chk($uid));
	
	my $q_ip = $S->dbh->quote($ip);
	
	my ($rv, $sth);
	# First record the rating record-- check for existing
	my $flag = $S->_is_current_rating($sid, $cid);
	if ($flag) {
		if($rating >= 0){
			($rv, $sth) = $S->db_update({
				DEBUG => 0,
				WHAT => 'commentratings',
				SET => qq|rating = '$rating', rating_time = NOW(), rater_ip = $q_ip|,
				WHERE => qq|sid = '$sid' AND cid = $cid AND uid = $uid|});
			}
		else {
			($rv, $sth) = $S->db_delete({
				FROM => 'commentratings',
				WHERE => qq|sid = '$sid' AND cid = $cid AND uid
= $uid|
					});
			}
	} else {
		return $comm_uid if $rating < 0;
		($rv, $sth) = $S->db_insert({
			DEBUG => 0,
			INTO => 'commentratings',
			COLS => 'uid, sid, cid, rating, rating_time, rater_ip',
			VALUES => qq|$uid, '$sid', $cid, '$rating', NOW(), $q_ip|});
	}
	$sth->finish;
	
	$comm_uid = $S->recalculate_one_rating($sid, $cid, $comm_uid, $test_uid, $flag);
	# clear troll rating limit. We'll let trl_chk update that next time
	# it runs.
	$S->cache->remove("trl_$uid") if ($rating <= 0);
	# THIS NEEDS FIXED TO USE THE DECR FUNC
	#my $tru = $S->cache->remove("trl_$uid");
	#$tru--; $tru = '0E0' if $tru <= 0;
	#$S->cache->store("trl_$uid", $tru, "+6h") if $rating == 0;
	
	$S->run_hook('comment_rate', $sid, $cid, $uid, $rating);

	return $comm_uid;
}	
	
sub recalculate_one_rating {
	my $S = shift;	
	my ($sid, $cid, $comm_uid, $test_uid, $flag) = @_;

	# Then update the story's total rating
	my ($rating_total, $num_ratings) = $S->_current_rating_stats($sid, $cid);
	
	$num_ratings = undef unless ($num_ratings >= 1);
	
	my $new_av = undef;
	if ($num_ratings >= 1) {
		$new_av = ($rating_total / $num_ratings);
	}
	
	#warn "Rating is now $new_av\n";
	
	# Now file the new rating.
	$S->_update_comment_rating($sid, $cid, $new_av, $num_ratings, $flag);
	
	# Get the uid of the poster for mojo...
	if ($S->{UI}->{VARS}->{use_mojo}) {
		$comm_uid = $test_uid;
	}
	
	return $comm_uid;
}


sub _get_uid_of_comment {
	my $S = shift;
	my ($sid, $cid) = @_;
	
	my $f_sid = $S->{DBH}->quote($sid);
	my $f_cid = $S->{DBH}->quote($cid);
	
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'uid',
		FROM => 'comments',
		WHERE => qq|sid = $f_sid AND cid = $f_cid|});
	
	my $uid = $sth->fetchrow();
	$sth->finish();
	return $uid;
}


sub _verify_rating {
	my $S = shift;
	my $rating = shift;
	
	if ($rating > $S->{UI}->{VARS}->{rating_max}) {
		$rating = $S->{UI}->{VARS}->{rating_max};
	}
	
	my $min = $S->{UI}->{VARS}->{rating_min};
	my $sub_min = $min;
	if (($S->{UI}->{VARS}->{use_mojo}) &&
		($S->{TRUSTLEV} == 2 || $S->have_perm('super_mojo'))) {
		my $hide_rating = $S->{UI}->{VARS}->{hide_rating_value};
		$sub_min = ($hide_rating == '') ? ($min - 1) : $hide_rating;
	}
	
	if ($rating < $min && $rating != $sub_min) {
		$rating = $min unless $rating == -1; # gotta be able to unrate
	}
	
	return $rating;
}


sub _update_comment_rating {
	my $S = shift;
	my ($sid, $cid, $rating, $num, $flag) = @_;
	$rating = 'NULL' unless (defined($rating));
	$num = '-1' unless (defined($num));
	$flag = 0;
	
	my $column_to_update = ($num >= $S->{UI}->{VARS}->{minimum_ratings_to_count}) ?
	                       'points' :
						   'pre_rating';
	
	# Hack to make mysql work right.
	# wtf, rusty. this had better be good
	my ($rv, $sth);
	#my ($rv, $sth) = $S->db_update({
	#	ARCHIVE => $S->_check_archivestatus($sid),
	#	WHAT => 'comments',
	#	SET => qq|$column_to_update = "1"|,
	#	WHERE => qq|sid = '$sid' AND cid = $cid|,
	#	DEBUG => 0});
	#$sth->finish();
	
	my $r = ($rating eq 'NULL') ? 'NULL' : qq|"$rating"|;
	
	my $rate_q = {
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'comments',
		SET => qq|$column_to_update = $r|,
		WHERE => qq|sid = '$sid' AND cid = $cid|,
		DEBUG => 0};
	
	unless ($flag) {
		$rate_q->{SET} .= qq|, lastmod = '$num'|;
	}
	# gotta handle the weird case of unrating screwing stuff up
	if($num < $S->{UI}->{VARS}->{minimum_ratings_to_count}) {
		$rate_q->{SET} .= qq|, points = NULL|;
		}
	
	($rv, $sth) = $S->db_update($rate_q);
	$sth->finish;
	
	return;
}

sub _current_rating_stats {
	my $S = shift;
	my ($sid, $cid) = @_;
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'rating, rater_ip',
		FROM => 'commentratings',
		WHERE => qq|sid = '$sid' AND cid = $cid|});
	if ($rv eq '0E0') {
		$rv = 0;
	}
	
	my $total = 0;
	my $rater_ips;
	my $count = 0;
	while (my $rating = $sth->fetchrow_hashref) {
		next if ($S->{UI}->{VARS}->{filter_ratings_by_ip} &&
		         exists $rater_ips->{$rating->{rater_ip}});
		$total += $rating->{rating};
		$count++;
		$rater_ips->{$rating->{rater_ip}} = 1;
	}
	$sth->finish;
	
	return ($total, $count);
}


sub _is_current_rating {
	my $S = shift;
	my ($sid, $cid) = @_;
	my $uid = $S->{UID};
	
	my ($rv, $sth) = $S->db_select({
		DEBUG => 0,
		WHAT => 'rating',
		FROM => 'commentratings',
		WHERE => qq|sid = '$sid' AND cid = $cid AND uid = $uid|});
	
	if ($rv eq '0E0') {
		$rv = 0;
	}
	$sth->finish;

	return $rv;
}

sub _check_rating_perm {
	my $S = shift;
	my ($sid, $cid) = @_;
	
	return 0 unless ($S->have_perm('comment_rate'));
	
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
		WHAT => 'uid, points',
		FROM => 'comments',
		WHERE => qq|sid = '$sid' AND cid = $cid|});
	
	my $row = $sth->fetchrow_hashref;
	$sth->finish;
	my $comp_uid = $row->{uid};
	
	if ($S->{UID} == $comp_uid) {
		return 0;
	}
	
	# Check if the comment is hidden, and if so, do you have permission to rate it
	my $hide_thresh = $S->{UI}->{VARS}->{hide_comment_threshold} || $S->{UI}->{VARS}->{rating_min};
	if ($row->{points} != undef) {
		if ( ($row->{points} < $hide_thresh) &&
			!( ($S->{TRUSTLEV} == 2) || ($S->have_perm('super_mojo')))) {
			# No permissiuon to view == no permission to rate
			return 0;
		}		
	}
	return 1;
}

sub _delete_ratings {
	my $S = shift;
	my $sid = shift;
	my $cid = shift;
	my $uid = shift;
	
	my ($rv, $sth) = $S->db_delete({
		FROM => 'commentratings',
		WHERE => qq|sid = '$sid' AND cid = $cid|});
	
	if ($rv) {
		$S->update_mojo({$uid => 1});
	}
	
	return;
}

sub trl_chk {
	# returns the number of troll ratings left for the day
	my $S = shift;
	my $uid = shift;
	# sort of unusual case here. If we *aren't* using troll rating limits,
	# we return *true*. Weird, huh?
	return 1 if !$S->{UI}->{VARS}->{use_troll_rate_limit} || $S->have_perm('evade_troll_rate');;
	return 0 if (!$S->have_perm('zero_rate'));

	my $trl_num = $S->{UI}->{VARS}->{'troll_rate_limit'};

	# check the cache first.
	my $trl = $S->cache->fetch("trl_$uid");
	my $trl_ret; # might need to keep this separate

	# if we're not defined, we need to figure out how many troll
	# ratings we have left. unfortunately, the cache treats 0 as undefined,
	# even if we actually *want* a zero in there, so we need to put in
	# some sort of place holder
	if(!defined($trl)){
		my ($rv, $sth) = $S->db_select({
			WHAT => "$trl_num - count(*)",
			FROM => 'commentratings',
			WHERE => qq|uid = $uid AND rating_time > DATE_SUB(NOW(), INTERVAL 1 DAY) AND rating = 0|
			});
		my $trl_res = $sth->fetchrow;
		$sth->finish;
		$trl_ret = $trl_res;
		$trl = ($trl_res == 0) ? '0E0' : $trl_res;
		# cache that mother.
		$S->cache->store("trl_$uid", $trl, "+2h");
		}
	else {
		# translate '0E0' if needed
		$trl_ret = ($trl eq '0E0') ? 0 : $trl;
		}
	# and send it back!
	return $trl_ret;
	}


1;
