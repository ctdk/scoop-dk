package Scoop;
use strict;
my $DEBUG = 0;


sub subscribe {
	my $S = shift;
	
	unless ($S->have_perm('allow_subscription')) {
		$S->{UI}->{BLOCKS}->{CONTENT} .= qq|
		%%norm_font%%$S->{UI}->{BLOCKS}->{subscribe_denied_message}%%norm_font_end%%|;
		return;
	};

	my $sub_purchase_type_list = $S->sub_purchase_type_list();

	my $page = qq|
	<table border=0 cellpadding=0 cellspacing=0 width="99%">
	  <tr>
		<td bgcolor="%%title_bgcolor%%">
		  %%title_font%%Subscribe%%title_font_end%%
		</td>
       </tr>
	</table>
	<table border=0 cellpadding=8 cellspacing=0 width="99%">
	<tr>
		<td>
			%%norm_font%%
			%%subscribe_intro_text%%
			%%norm_font_end%%
		</td>
	</tr>
	<tr>
		<td>
			%%norm_font%%
			$sub_purchase_type_list
			%%norm_font_end%%
		</td>
	</tr>
        <tr>
                <td>
                        %%norm_font%%
                        %%subscribe_end_text%%
                        %%norm_font_end%%
                </td>
        </tr>
	</table>
	|;

	$S->{UI}->{BLOCKS}->{CONTENT} .= $page;
	return;
}


sub sub_purchase_type_list {
	my $S = shift;
	
	# are we a gift?
	my $ruid = shift;
	my ($rv, $sth) = $S->db_select({
		WHAT => '*',
		FROM => 'subscription_types',
		ORDER_BY => 'cost DESC'
	});
	
	my @types;
	while (my $r = $sth->fetchrow_hashref()) {
		push @types, $r;
	}
	$sth->finish();
	
	my $page = qq|
	<table border=0 cellpadding=8 cellspacing=0 width="100%">|;
	
	foreach my $type (@types) {
		# Check renewable status
		next if ($S->sub_check_renewable($type->{type}));
		$type->{cost_print} = '$'.$type->{cost};
		if ($type->{cost} eq '0.00') {
			$type->{cost_print} = 'Free!';
		}
		my ($max, $buy, $recur);
		if ($type->{max_time}) {
			my $end = ($type->{max_time} > 1) ? 's' : '';
			$max = qq|<b>Limit:</b> $type->{max_time} $type->{duration}$end<br />| unless ($type->{duration} eq 'forever');
		}
		# For recurrable subs
		my $radiosub;
		if ($type->{recurrable}) {
			$recur = qq|<br /><input type="radio" name="subrecur" value="recur"> <b>Purchase</b> a $type->{duration}ly recurring subscription.<br />|;
			# set up a radio button for the normal subs too if
			# the sub's recurrable
			$radiosub = qq|<input type="radio" name="subrecur" value="normal"> |;
			}
		# special stuff for gift subs. Woo!
		my $giftstuff;
		if ($ruid) {
			my $ganon = ($S->{UID} > 0) ? qq|Give anonymously? <input type="checkbox" name="giveanon" value=1><br />| : '';
			$giftstuff = qq|<input type="hidden" name="giftuid" value="$ruid"><input type="hidden" name="giveruid" value="$S->{UID}">$ganon<b>Personal message (limit 175 characters):</b><br /><textarea cols="25" rows="5" name="givemsg"></textarea><br />|;
			}
		
		$buy = qq|
		<form action="%%rootdir%%/subpay" method="post">
		<input type="hidden" name="type" value="$type->{type}">
		$giftstuff
		$radiosub<b>Purchase</b> |;
		
		my $durval = $type->{duration};
		$durval .= 's' if($durval ne 'forever');
		if ($type->{max_time} == 1) {
			$buy .= qq|
		<input type="hidden" name="$durval" value="1">|;
			$buy .= qq|<b>1</b> $type->{duration}<br />| if ($durval ne 'forever');
		} else {
			$buy .= qq|
		<input type="text" name="$durval" size=3> $durval|;
			if ($type->{max_time}) {
				$buy .= qq|(Limit $type->{max_time})|;
			}
		}
		$buy .= $recur;
		# zip code & international stuff
		$buy .= qq|<b>Zip Code:</b> <input type="text" name="zip" size="5" /><br /><b>International subscriptions,</b> check here: <input type="checkbox" name="international" /><br />|;
		$buy .= qq| <small><input type="submit" name="buy" value="Buy &gt;"></small></form>|;
		
		$page .= qq|
		<tr>
			<td>
			%%norm_font%%
			<b>$type->{type}</b><br />
			$type->{description}<br />
			<b>Price:</b> $type->{cost_print}<br />
			$max
			$buy
			%%norm_font_end%%
			</td>
		</tr>|;
	}

	$page .= qq|
	</table>|;
	
	return $page;
}

sub sub_check_renewable {
	my $S = shift;
	my $type = shift;
	my $t_data = $S->sub_get_type($type);
	return 0 if ($t_data->{renewable});
		
	my $q_type = $S->dbh->quote($type);
	
	# Check for free type
	my ($rv, $sth) = $S->db_select({
		WHAT => 'uid',
		FROM => 'subscription_info',
		WHERE => "uid = $S->{UID} AND type = $q_type"
	});
	my $check = $sth->fetchrow();
	$sth->finish();
	
	return 1 if ($check);
	
	# If not found, find out what kind the free sub mirrors
	($rv, $sth) = $S->db_select({
		WHAT => 'type',
		FROM => 'subscription_types',
		WHERE => qq|perm_group_id = '$t_data->{perm_group_id}' AND type != $q_type|
	});
	
	while (my $mirror_type = $sth->fetchrow()) {
		my ($rv2, $sth2) = $S->db_select({
			WHAT => 'uid',
			FROM => 'subscription_info',
			WHERE => qq|uid = $S->{UID} AND type = '$mirror_type'|
		});
		my $check = $sth2->fetchrow();
		$sth2->finish();
		return 1 if ($check);
	}	
	$sth->finish();
	
	return 0;
}

sub sub_get_type {
	my $S = shift;
	my $type = shift;
	
	my $q_type = $S->dbh->quote($type);
	my ($rv, $sth) = $S->db_select({
	  WHAT  => '*',
	  FROM  => 'subscription_types',
	  WHERE => "type = $q_type",
	  DEBUG => 0
	});
	my $type_data = $sth->fetchrow_hashref();
	$sth->finish();
	return $type_data;
}


sub sub_get_billing_price {
	my $S = shift;
	my $in = shift;

	# Get basic price
	my ($price, $trash) = $S->sub_calculate_purchase_cost($in->{type}, $in->{months});
	
	# Check for dupes
	$price = $S->sub_adjust_for_dupes($price, $in->{ctype});

	return $price;
}
	
sub sub_get_price {
	my $S = shift;
	my $in = shift;
	
	my $type = $S->dbh->quote($in->{type});
	
	# Get the unit price
	my ($rv, $sth) = $S->db_select({
		WHAT => 'cost',
		FROM => 'subscription_types',
		WHERE => qq|type = $type|
	});
	my $per_month = $sth->fetchrow();
	$sth->finish();
	
	return undef unless ($per_month);
	
	# Calculate total
	my $price = sprintf("%1.2f", ($in->{months} * $per_month));
	
	return $price;
}

sub sub_adjust_for_dupes {
	my $S = shift;
	my $price = shift;
	my $ctype = shift;
	
	my $dupe = 1;
	while ($dupe) {
		my ($rv, $sth) = $S->db_select({
			WHAT  => 'COUNT(*)',
			FROM  => 'subscription_payments',
			WHERE => qq{uid = $S->{UID}  AND 
			            cost = "$price" AND
						auth_date = NOW() AND
						pay_type = "$ctype"}
		});
		
		# If zero, we'll break out of the loop.
		$dupe = $sth->fetchrow();
		$sth->finish();
		warn "Dupe: $dupe. Price: $price\n" if $DEBUG;
		$price -= 0.01 if ($dupe);
	}	
	
	return $price;
}

sub sub_activate_immediate {
	my $S = shift;
	my $type = shift;
	my $months = shift;

	my ($r, $price) = $S->sub_calculate_purchase_cost($type, $months);

	return unless ($price == 0);

	# Ok, price is indeed zero, so just update the subscription info
	$S->sub_add_to_subscription($months, $type);

	# Change the user's group
	my $change = $S->sub_update_user_group($type);

	if ($change eq 'manual') {
		# Send an admin email
		$S->sub_email_manual_change($months, $type, $S->{UID});
	} else {
		# Send an email to the user.
		$S->sub_email_success($months, $type, $S->{UID});
	}

	my $return = qq|%%norm_font%%
	<center><b>Your subscription is now active!</b> Thank you for supporting $S->{UI}->{VARS}->{sitename}.</center>
	%%norm_font%%|;

	return $return;
}
	
		
sub sub_finish_subscription {
	my $S = shift;
	my $in = shift;
	my $oid = shift;
	my $total = shift;
	my $recur = shift;

	my $uid = $in->{uid} || $S->{UID};

	# Write the payment record
	return unless $S->sub_save_payment($oid, $total, $in->{ctype}, $in->{type}, $uid, $in->{subfrom}, $in->{zip});

	# Update the sub info record
	return unless $S->sub_add_to_subscription($in->{months}, $in->{type}, $uid, $in->{units}, $recur);

	# Change the user's group
	my $change = $S->sub_update_user_group($in->{type}, $uid);
	# clear the user data cache
	#$S->cache->remove("ud_$uid");
	if ($in->{subfrom}){
		$S->sub_email_gift($in->{months}, $in->{type}, $uid, $in->{subfrom}, $in->{submsg});
		}
	elsif ($change eq 'manual') {
		# Send an admin email
		$S->sub_email_manual_change($in->{months}, $in->{type}, $uid);
	} else {
		# Send an email to the user.
		$S->sub_email_success($in->{months}, $in->{type}, $uid);
	}

	return;
}

sub sub_update_user_group {
	my $S = shift;
	my $type = shift;
	my $uid = shift || $S->{UID};
	my $user = $S->user_data($uid);
	
	# First, check the user's current group, to see if it has 
	# "subscription_allow_group_change" perm
	return 'manual' unless ($S->have_perm("suballow_group_change", $user->{perm_group}));

	my $type_info = $S->sub_get_type($type);
	my $q_group = $S->dbh->quote($type_info->{perm_group_id});

	my ($rv, $sth) = $S->db_update({
		WHAT => 'users',
		SET => qq|perm_group = $q_group|,
		WHERE => qq|uid = $uid|
	});
	$sth->finish();

	# And refresh the perms
	$S->_refresh_group_perms();

	return $rv;
}	


sub sub_save_payment {
	my $S        = shift;
	my $oid      = shift;
	my $total    = shift;
	my $pay_type = shift;
	my $type     = shift;
	my $uid 	 = shift || $S->{UID};
	my $subfrom  = shift;
	my $zip = shift;
	
	my $q_oid     = $S->dbh->quote($oid);
	my $q_total   = $S->dbh->quote($total);
	my $q_paytype = $S->dbh->quote($pay_type);
	my $q_type    = $S->dbh->quote($type);
	my $q_subfrom = $S->dbh->quote($subfrom);
	my $q_zip     = $S->dbh->quote($zip);

	my ($rv, $sth) = $S->db_insert({
		INTO   => 'subscription_payments',
		COLS   => 'uid, order_id, cost, pay_type, auth_date, final_date, paid, type, subfrom, zip',
		VALUES => qq|$uid, $q_oid, $q_total, $q_paytype, NOW(), NOW(), 1, $q_type, $q_subfrom, $q_zip|
	});
	$sth->finish();
	return $rv;
}

sub sub_add_to_subscription {
	my $S      = shift;
	my $months = shift;
	my $type   = shift;
	my $uid	   = shift || $S->{UID};
	my $units = shift;
	my $recur = shift;
	
	if($units){
  	    if($units =~ /months/){}
	    if($units =~ /year/){
	    	$months *= 12;
		}
	    if($units =~ /forever/){
	        $months *= 10000;
		}
	    if($units =~ /lifetime/){
                $months *= 10000;
                }
	    }
	my ($new_exp, $existing) = $S->sub_new_expiration($type, $months, $uid);
	warn "New expiration is $new_exp\n" if ($DEBUG);
	
	# Check for an inactive sub record, if not existing
	unless ($existing) {
		my ($rv, $sth) = $S->db_select({
			WHAT => 'uid',
			FROM => 'subscription_info',
			WHERE => "uid=$uid"
		});
		$existing = $sth->fetchrow();
		$sth->finish();
	}
	
	($existing) ? $S->sub_update_subscription($months, $type, $new_exp, $uid, $recur) :
	              $S->sub_create_subscription($months, $type, $new_exp, $uid, $recur);
	
	return 1;
}

sub sub_update_subscription {
	my $S = shift;
	my $months = shift;
	my $type = shift;
	my $new_exp = shift;
	my $uid	   = shift;
	my $recur = shift;
	my $q_type  = $S->dbh->quote($type);
	$recur = ($recur) ? 1 : 0;
	my ($rv, $sth) = $S->db_update({
		WHAT => 'subscription_info',
		SET  => qq|expires=$new_exp, last_updated=NOW(), updated_by='system', active=1, type=$q_type, recurring = $recur|,
		WHERE => qq|uid=$uid|
	});
	$sth->finish();
	return;
}

sub sub_create_subscription {
	my $S = shift;
	my $months = shift;
	my $type = shift;
	my $new_exp = shift;
	my $uid	   = shift;
	my $recur = shift;
	my $q_type  = $S->dbh->quote($type);
	$recur = ($recur) ? 1 : 0;
	my ($rv, $sth) = $S->db_insert({
		INTO => 'subscription_info',
		COLS => 'uid, expires, created, last_updated, updated_by, active, type, recurring',
		VALUES => qq|$uid, $new_exp, NOW(), NOW(), 'system', 1, $q_type, $recur|
	});
	$sth->finish();
	return;
}

sub sub_calculate_purchase_cost {
	my $S = shift;
	my $type = shift;
	my $months = shift;
	my $units = shift;
	# little different if we're a gift sub
	my $uid = shift || $S->{UID};
	my $return;
	
	# Find the base cost
	my $in = {};
	$in->{type} = $type;
	$in->{months} = $months;
	$in->{units} = $units;
	my $price = $S->sub_get_price($in);
	my $type_data = $S->sub_get_type($type);

	# Recurring subs, theoretically, should be easier. Still not quite
	# sure what to do with proration though.
	if($S->cgi->param('subrecur') eq 'recur'){
		$return = qq|<p>You are purchasing a recurring $type_data->{type} subscription, which will automatically renew every $type_data->{duration} until you cancel it.</p>|;
		# check if they have an existing subscription
		my ($old_type, $remaining_days, $value_remaining) =  $S->sub_check_existing_subscription($uid);
		if ($old_type){
			my $td = $S->sub_get_type($old_type);
			$return .= qq|<p>You already have a $td->{type} with $remaining_days days remaining and a value of \$$value_remaining. We are currently unable to offer automatic refunds, so you may wish to cancel the subscription process now and wait until your old subscription expires to sign up for a recurring subscription, or <a href="/contactus">contact us</a> for a refund.</p>|;
			}
		# but hey, at least we can bust out early
		return ($price, $return);
		}
	
	my $pl = ($months == 1) ? '' : 's';
	my $length = ($units eq 'forever') ? "a lifetime" : "$months $units";
	$return .= qq|<p>You are ordering <b>$length</b> of $type, for a total cost of 
<b>\$$price</b>.</p>|;

	# Find out if the user is already a subscriber
	my ($old_type, $remaining_days, $value_remaining) = $S->sub_check_existing_subscription($uid);
	if ($old_type) {
		$return .= qq|<p>You are already subscribed as $old_type. |;
		
		my $old_type_data = $S->sub_get_type($old_type);
	
		if ($old_type eq $type) {
			$return .= qq|
				Your existing subscription has <b>$remaining_days</b> days remaining. 
				Your new subscription period will be added to that.</p>|;
		} elsif ($price - $value_remaining > 0) {
			$return .= qq|
				Your existing subscription has <b>$remaining_days</b> days remaining, with a prorated value of <b>\$$value_remaining</b>. 
				Your new subscription will start immediately, with this amount subtracted from the total cost.</p>|;
			
			# subtract the remaining value from the base price
			$price -= $value_remaining;
			
			$return .= qq|<p>The final price for this subscription is <b>\$$price</b></p>|;
			
		} elsif ($price - $value_remaining < 0) {
			my $minimum = ($value_remaining % $type_data->{cost} > 0) ? 
				(int($value_remaining / $type_data->{cost}) + 1) :
				($value_remaining / $type_data->{cost});

			$return .= qq|
				Your existing subscription has <b>$remaining_days</b> days remaining, with a prorated value of <b>\$$value_remaining</b>. 
				Your altered subscription must cost at least <b>\$$value_remaining</b>, as we cannot currently provide refunds. 
				You may change your subscription, but if you wish to subscribe at this price, it must be for at least <b>$minimum</b> months.
				Please use your back button to change your purchase amount.</p>|;
				
			$price = 'ERROR';
		} elsif ($price - $value_remaining == 0) {
			$return .= qq|
				Your existing subscription has <b>$remaining_days</b> days remaining, with a prorated value of <b>\$$value_remaining</b>. 
				Your new subscription will start immediately, with this amount subtracted from the total cost.</p>
				<p>Your total cost for this change is <b>\$0.00</b>, so we'll just skip the whole billing process and activate 
				your new subscription right now. Please click the button below to complete this change.</p>|;
			$price -= $value_remaining;
		}
	}
		

	return ($price, $return);
}

sub sub_check_existing_subscription {
	my $S = shift;
	my $uid = shift;
	
	my ($rv, $sth) = $S->db_select({
		WHAT => 'expires, type',
		FROM => 'subscription_info',
		WHERE => qq|uid = $uid AND active = 1|});
	my ($expires, $type) = $sth->fetchrow();
	$sth->finish();
	
	return unless ($expires && $type);
	
	my $type_data = $S->sub_get_type($type);
	# let's squash this prorating thing once & for all
	my $cdiv;
	if ($type_data->{duration} eq 'month'){
		$cdiv = 31;
		}
	elsif ($type_data->{duration} eq 'year'){
		$cdiv = 365;
		}
	else {
		# Gotta figure out what to do with lifetime. Actually, once
		# you have a lifetime sub, you really don't need to subscribe
		# again. Hmmm. Well, let's figure something out.
		$cdiv = (int((($expires - time) / 86400)) + 1);
		}
	my $day_cost = $type_data->{cost} / $cdiv;
	my $now = time;
	
	# Subtract the current time from the time the sub expires
	# to determine remaining seconds on the sub. Then divide by
	# 86400 to get remaining days, then truncate that to integer portion only, 
	# and add a day to be customer-friendly in estimating.
	my $remaining_days = (int((($expires - $now) / 86400)) + 1);
	
	my $vr = $remaining_days * $day_cost;
	my $vr_formatted = sprintf("%1.2f", $vr);

	return ($type, $remaining_days, $vr_formatted);
}

sub sub_new_expiration {
	my $S = shift;
	my $type = shift;
	my $months = shift;
	my $uid = shift;
		
	my ($old_type, $remaining_days, $value_remaining) = $S->sub_check_existing_subscription($uid);
	warn "Old: $old_type, Remain: $remaining_days, Value: $value_remaining\n" if ($DEBUG);
	
	return ((time + ($months * 2678400)), 0) unless ($old_type);
	
	warn "Not new. New type is $type\n" if ($DEBUG);
	
	my $old_type_data = $S->sub_get_type($old_type);
	my $type_data = $S->sub_get_type($type);
	my $now = time;
	
	my $new_exp;
	if ($old_type eq $type) {
		warn "Same type\n" if ($DEBUG);
		$new_exp = $now + ($remaining_days * 86400) + ($months * 2678400);
	} else {
		warn "Different type\n" if ($DEBUG);
		$new_exp = $now + ($months * 2678400);
	}
	
	warn "Sending back a new expiration of $new_exp\n" if ($DEBUG);
	return ($new_exp, 1);
}
	

sub sub_email_manual_change	{
	my $S = shift;
	my $months = shift;
	my $type = shift;
	my $uid = shift;
	my $user = $S->user_data($uid);

	my $message = $S->{UI}->{BLOCKS}->{sub_manual_change_email};
	my $url = $S->{UI}->{VARS}->{site_url}.$S->{UI}->{VARS}->{rootdir}."/user/uid:$uid";

	$message = $S->sub_escape_mail($message, {months=>$months, type=>$type, url=>$url, nick=>$user->{nickname}});
	my $subj = 'Manual subscription change needed';

	foreach my $to (split /,/, $S->{UI}->{VARS}->{admin_alert}) {
		$S->mail($to, $subj, $message);
	}

	return;
}

sub sub_email_success {
	my $S = shift;
	my $months = shift;
	my $type = shift;
	my $uid = shift || $S->{UID};

	my $to = $S->get_email_from_uid($uid);
	my $message = $S->{UI}->{BLOCKS}->{sub_email_success};
	my $subj = "Thank you for subscribing to $S->{UI}->{VARS}->{sitename}";

	# $%^@&*& bug That Would Not Die!!!!
	my $sub = $S->sub_current_subscription_info($uid);
	my $f_exp = &Time::CTime::strftime('%e %b %Y', localtime($sub->{expires}));

	my $in = {
		months=>$months, 
		type=>$type,
		expiration=>$f_exp,
		duration => $sub->{duration}
	};

	$message = $S->sub_escape_mail($message, $in);
	my $rv = $S->mail($to, $subj, $message);

	return;
}

sub sub_email_gift {
	my $S = shift;
        my $months = shift;
        my $type = shift;
        my $uid = shift;
	my $subfrom = shift;
	my $submsg = shift;

        my $to = $S->get_email_from_uid($uid);
        my $message = $S->{UI}->{BLOCKS}->{sub_email_gift};
	my $qui = ($subfrom == -1) ? "An anonymous stranger" : $S->get_nick_from_uid($subfrom);
        my $subj = "You have received a gift subscription to $S->{UI}->{VARS}->{sitename}";

        # $%^@&*& bug That Would Not Die!!!!
        my $sub = $S->sub_current_subscription_info($uid);
        my $f_exp = &Time::CTime::strftime('%e %b %Y', localtime($sub->{expires}));

	if ($submsg) {
		$submsg = qq|\r\n$qui also sent this message to you:\r\n$submsg|;
		}
        my $in = {
                months=>$months,
                type=>$type,
                expiration=>$f_exp,
                duration => $sub->{duration},
		qui => $qui,
		submsg => $submsg
        };

	$message = $S->sub_escape_mail($message, $in);
        my $rv = $S->mail($to, $subj, $message);

        return;
	}
		
sub sub_escape_mail {
	my $S = shift;
	my $msg = shift;
	my $in = shift;

        # flip some stuff around, if need be
        if($in->{months} != 1) {
                $in->{duration} .= "s";
                }
        if($in->{duration} eq 'forever'){
                $in->{months} = '';
                $in->{duration} = "a lifetime's worth of subscription";
		$in->{expiration} = '';
                }
	else {
		$in->{expiration} = "Your subscription will expire on $in->{expiration}";
		}

	$msg =~ s/%%NICK%%/$in->{nick}/g;
	$msg =~ s/%%TYPE%%/$in->{type}/g;
	$msg =~ s/%%MONTHS%%/$in->{months}/g;
	$msg =~ s/%%DURATION%%/$in->{duration}/g;
	$msg =~ s/%%URL%%/$in->{url}/g;
	$msg =~ s/%%EXP_DATE%%/$in->{expiration}/g;
	$msg =~ s/%%GIVER%%/$in->{qui}/g;
	$msg =~ s/%%SUBMSG%%/$in->{submsg}/g;
	$msg =~ s/%%sitename%%/$S->{UI}->{VARS}->{sitename}/g;
	$msg =~ s/%%site_url%%/$S->{UI}->{VARS}->{site_url}/g;
	$msg =~ s/%%local_email%%/$S->{UI}->{VARS}->{local_email}/g;

	return $msg;
}

sub sub_user_info {
	my $S = shift;
	my $uid = shift;
	return '' unless $S->{UI}->{VARS}->{use_subscriptions}
		&& $S->have_perm('allow_subscription', $S->user_data($uid)->{perm_group});

	my $sub = $S->sub_current_subscription_info($uid);

	return $S->{UI}->{BLOCKS}->{subscribe} unless ($sub);

	my $expires = &Time::CTime::strftime('%e %b %Y', localtime($sub->{expires}));
	
	my $info = "<p>You are currently subscribed as \"$sub->{type}\".<br />
	Your subscription expires on $expires.<br />
	You may alter or extend your subscription <a href=\"%%rootdir%%/subscribe\">here</a>.
	</p>";
	
	return $info;
}

sub sub_current_subscription_info {
	my $S = shift;
	my $uid = shift || $S->{UID};
	
	my ($rv, $sth) = $S->db_select({
		FORCE_MASTER => 1,
		WHAT => 'subscription_info.*, duration',
		FROM => 'subscription_info left join subscription_types using (type)',
		WHERE => "uid = $uid AND active = 1"
	});
	
	my $sub = $sth->fetchrow_hashref();
	$sth->finish();
	
	return $sub;
}

1;
