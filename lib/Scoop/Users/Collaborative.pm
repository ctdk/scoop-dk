package Scoop;
use strict;

sub create_collab_user {
	my $S = shift;
	return "<h1>Permission Denied.</h1>" unless $S->have_perm('create_collab_user');
	my $uid = $S->{UID};
	my $cnick = $S->cgi->param('cnick');
	
	my $form = $S->{UI}->{BLOCKS}->{collab_user_form};
	# eh, we're just figuring out the basics right now
	my $error;
	if ($S->cgi->param('submit') && $cnick){
		$error = $S->write_collab_user($cnick);
		undef $cnick if $error;
		}
	$form =~ s/%%ERROR%%/$error/;
	if($cnick && !$error){
		return $S->{UI}->{BLOCKS}->{collab_user_success};
		}

	return $form;
	}

sub write_collab_user {
	my $S = shift;
	my $cnick = shift;
	my $error;
	undef $cnick if $error .= $S->filter_new_username($cnick);
	undef $cnick if $error .= $S->check_for_user($cnick);
	# make it look pretty later
	return $error if $error;

	# if we're here, great. We're making the collaborative user.
	my $dbnick = $S->dbh->quote($cnick);
	my $group = $S->dbh->quote($S->{UI}->{VARS}->{collab_group});
	my $ip = $S->dbh->quote($S->{REMOTE_IP});
	my $pass = 'x'; # dummy val
	# eh, be safe
	my ($rv, $sth) = $S->db_insert({
		INTO => 'users',
		COLS => 'nickname, passwd, perm_group, creation_ip, creation_time, is_collab',
		VALUES => qq|$dbnick, '$pass', $group, $ip, now(), 1|
		});
	return "Error creating new collaborative user! DB said: " . $DBI::errstr if !$rv;
	# initial collab_user info
	($rv, $sth) = $S->db_insert({
		INTO => 'collab_users',
		COLS => 'uid, owner',
		VALUES => "$S->{UID}, 1"
		});
	return;
	}

sub collab_user {
	my $S = shift;
	my $tool = $S->cgi->param('tool') || 'list';
	my $cuid = $S->cgi->param('cuid');

	

	}


	

1;
