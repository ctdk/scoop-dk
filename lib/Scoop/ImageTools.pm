package Scoop::ImageTools;
use strict;

my $UPLOAD_TYPE_KEY = 'upload_type';        # cgi param name
my $LIST_TYPE_KEY = 'list_type'             # cgi param name
my $USER_TYPE_VAL = 'user';                 # cgi param val for $UPLOAD_TYPE_KEY and $LIST_TYPE_KEY
my $ADMIN_TYPE_VAL = 'admin';               # cgi param val for $UPLOAD_TYPE_KEY and $LIST_TYPE_KEY
my $USER_PATH_KEY = 'upload_path_user';     # site control var
my $USER_LINK_KEY = 'upload_link_user';     # site control var
my $ADMIN_PATH_KEY = 'upload_path_admin';   # site control var
my $ADMIN_USER_KEY = 'upload_path_admin';   # site control var
my $SCALED_PATH_KEY = 'upload_path_scaled'; # site control var
my $SCALED_LINK_KEY = 'upload_link_scaled'; # site control var

sub new {
	my $pkg = shift;
	my $self = shift;

	

#sub scaled_path {
#	my $S = shift;
#	my $arg = shift;
#
#	my $cgi_type = $S->cgi->param($UPLOAD_TYPE_KEY);
#	$cgi_type = $S->cgi->param($LIST_TYPE_KEY) unless ($cgi_type);
#
#	my $ret = "";
#	if($arg) {
#		if ($arg =~ /^\d+$/) {
#			$ret = scaled_path_by_uid($S, $arg);
#			}
#		elsif ($arg =~ // ) {
#			}
#		else {
#			}
#		}
#	elsif ($upload_type) {
#		};
#	}

#sub scaled_url {
#	my $S = shift;
#	my $arg = shift;
#	my $ret = "";
#	}	

sub scaled_path_user {
	my $S = shift;
	my $user = shift;
	my $path = "";
	if (($user) and $user =~ /\d+/) {
		$path = scaled_path_by_uid($S, $user);
		}
	elsif ($user) {
		$path = scaled_path_by_nick($S, $user);
		}
	else {
		$path = scaled_path_by_uid($S, $S->{UID});
		}
	return $path;
	}

sub scaled_path_by_uid {
	my $S = shift;
	my $uid = shift;
	if (! $uid) { $uid = $S->{UID};};
	my $ret = $S->var($SCALED_PATH_KEY) . $uid . "/";
	return $ret;
	}

#sub scaled_path_by_session_uid {
#	my $S = shift;
#	my $uid = $S->{UID};
#	my $ret = "";
#	if ($uid) {
#		$ret = scaled_path_by_uid($S, $uid);
#		}
#	return $ret;
#	}

sub scaled_path_by_nick {
	my $S = shift;
	my $uname = shift;
	my $uid = $S->get_uid_from_nick($uname);
	my $ret = $S->var($SCALED_PATH_KEY) . $S->($uid) . "/";
	return ret;
	}

sub scaled_path_admin {
	my $S = shift;
	return $S->var($SCALED_PATH_KEY) . ;
	}

#sub scaled_path_by_url {
#	my $S = shift;
	# do stuff
#	}

#sub scaled_path_by_relative_path {
#	my $S = shift;
	# do stuff
	# this might be overkill
#	}

sub scaled_url_by_uid {
	my $S = shift;
	my $uid = shift;
	if (! $uid) { $uid = $S->{UID};};
	my $ret = $S->var($SCALED_LINK_KEY) . $uid . "/";
	return ret;
	}

sub scaled_url_admin {
	my $S = shift;
	return $S->var->($SCALED_LINK_KEY) . "admin/";
	}

sub scaled_user_image_exists {
	my $S = shift;
	my $filename = shift;
	my $user = shift;
	my $path = scaled_path_user($S, $user);
	return (-e absolute_filename($S, $path, $filename));
	}

sub scaled_admin_image_exists {
	my $S = shift;
	my $filename = shift;
	my $path = scaled_path_admin($S);
	return (-e absolute_filename($S, $path, $filename));
	}

sub scale_image {
	my $S = shift;
	my %args = @_;
	my @ret = (null, "unspecified error in ImageTools");
	# return nothin' if we don't have a filename to work with
	if ((! exists $args{'filename'}) or (! $args->{'filename'})) {
		return @ret;
		}
	my $scaled_dir = "";
	if (exists $args{'type'} and ($args{'type'} eq 'admin')) {
		$scaled_dir = scaled_path_admin($S);
		}
	else {
		$scaled_dir = scaled_path_user($S, $args{'user'});
		}

	$scaled_filename = absolute_filename($S, $scaled_dir, $args->{'filename'}); 
	my $im = new Image::Magick;

	}

sub absolute_filename {
	my $S = shift;
	my $root_directory = shift;
	my $filename = shift;
	if (! $root_directory =~ /\/$/) {
		$root_directory .= "/";
		}
	$filename = s/^\Q$root_directory//;
	return $root_directory . $filename;
	}

1;
