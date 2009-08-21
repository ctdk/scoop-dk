package Scoop::StoryCache;
use strict;

# Some basic functions for revamping the story cache, allowing for it to
# be moved into memcached, which ought to lead to improved performance.

# Currently, this plugs into the existing Scoop cache system, which should
# have the advantage of being able to work with either the native caching
# system or the memcached system. There is a possibility that it may be 
# better in the future to rewrite it to directly access the memcached system
# or an internal hash structure similar to the $S->{STORY_CACHE} hash that
# this object replaces.

sub new {
	my $pkg = shift;
	my $S = shift;

	my $class = ref($pkg) || $pkg;
	my $self = bless {}, $class;
	$self->{scoop} = $S; # God, do we even really need this?
	$self->{UID} = $S->{UID}; # put it somewhere easy to find
	# should check if this sets up a horrid mem leak or not...
	$self->{CACHE} = $S->{CACHE};

	# at least we *should* have less setting up to do. I think.
	return $self;
	}

sub cache	{ return $_[0]->{CACHE}		}

# interesting. We have to set the TZ as part of the key, since the formatting
# of the timestamp is done in the SQL query itself.

sub get {
	my $self = shift;
	my $sid = shift;
	my $tz = $self->{scoop}->pref('time_zone');
	$tz = uc($tz); # best make sure
	my $sd = $self->{SC}->{"${tz}_$sid"} ||= $self->cache->fetch("story_data_${tz}_$sid");
	return $sd;
	}

sub set {
	my $self = shift;
	my $sid = shift;
	my $tz = $self->{scoop}->pref('time_zone');
	$tz = uc($tz);
	my $data = shift;
	$self->{SC}->{"${tz}_$sid"} = $data;
	$self->cache->store("story_data_${tz}_$sid", $data);
	return;
	}

sub del {
	my $self = shift;
	my $sid = shift;
	#my $tz = $self->{scoop}->pref('time_zone');
	# If we're deleting an entry from the story_cache, then we'd best
	# get them all. Eventually, the time formatting stuff should be moved
	# out of the mysql query and handled elsewhere, but for now we'll just
	# have separate entries for each timezone.
	my %tzhash = $self->{scoop}->_timezone_hash();
	foreach my $tz (keys %tzhash){
		$tz = uc($tz);
		undef $self->{SC}->{"${tz}_$sid"};
		$self->cache->remove("story_data_${tz}_$sid");
		}
	return;
	}

# Woo. Special stuff for caching anon story data. I suppose it's a start.
# if it's called with just the sid, we're returning data, otherwise, we're
# setting it
sub asd {
	my $self = shift;
	return 0 if $self->{UID} < 0; # only do this for anon
	my $sid = shift;
	my $data = shift;
	return unless $sid;
	if(!$data){
		return $self->{ASD}->{"$sid"} ||= $self->cache->fetch("asd_$sid");
		}
	else {
		my $ctime = "+3m"; # want this to be configurable, but I'd
				   # rather avoid the db overhead here
		# guess we might as well stamp to be safe...
		# Or not! This leads to many unnecessary db hits
		# $self->cache->stamp("asd_$sid");
		$self->{ASD}->{"$sid"} = $data;
		$self->cache->store("asd_$sid", $data, $ctime);
		return;
		}
	# shouldn't end up here, but to be safe...
	return 0;
	}

sub asd_del {
	my $self = shift;
	my $sid = shift;
	undef $self->{ASD}->{"$sid"};
	$self->cache->remove("asd_$sid");
	# $self->cache->stamp("asd_$sid");
	return;
	}

# Modified versions of these functions for using with the array based story
# and story basic data functions

sub get_arr {
	my $self = shift;
	my $sid = shift;
	my $tz = $self->{scoop}->pref('time_zone');
	$tz = uc($tz); # best make sure
	my $sd = $self->{SCA}->{"${tz}_$sid"} ||= $self->cache->fetch("story_data_arr_${tz}_$sid");
	return $sd;
	}

sub set_arr {
	my $self = shift;
	my $sid = shift;
	my $tz = $self->{scoop}->pref('time_zone');
	$tz = uc($tz);
	my $data = shift;
	 $self->{SCA}->{"${tz}_$sid"} = $data;
	$self->cache->store("story_data_arr_${tz}_$sid", $data);
	return;
	}

sub del_arr {
	my $self = shift;
	my $sid = shift;
	my $id = ($sid =~ /\D/) ? $self->{scoop}->get_story_id_from_sid($sid) : $self->{scoop}->get_sid_from_story_id($sid);
	#my $tz = $self->{scoop}->pref('time_zone');
	# If we're deleting an entry from the story_cache, then we'd best
	# get them all. Eventually, the time formatting stuff should be moved
	# out of the mysql query and handled elsewhere, but for now we'll just
	# have separate entries for each timezone.
	my %tzhash = $self->{scoop}->_timezone_hash();
	foreach my $tz (keys %tzhash){
		$tz = uc($tz);
		undef $self->{SCA}->{"${tz}_$sid"};
		undef $self->{SCA}->{"${tz}_$id"};
		$self->cache->remove("story_data_arr_${tz}_$sid");
		$self->cache->remove("story_data_arr_${tz}_$id");
		}
	return;
	}

# Woo. Special stuff for caching anon story data. I suppose it's a start.
# if it's called with just the sid, we're returning data, otherwise, we're
# setting it
sub asd_arr {
	my $self = shift;
	return 0 if $self->{UID} < 0; # only do this for anon
	my $sid = shift;
	my $data = shift;
	return unless $sid;
	if(!$data){
		return $self->{ASDA}->{"$sid"} ||= $self->cache->fetch("asd_arr_$sid");
		}
	else {
		my $ctime = "+3m"; # want this to be configurable, but I'd
				   # rather avoid the db overhead here
		# guess we might as well stamp to be safe...
		# $self->cache->stamp("asd_arr_$sid");
		$self->{ASDA}->{"$sid"} = $data;
		$self->cache->store("asd_arr_$sid", $data, $ctime);
		return;
		}
	# shouldn't end up here, but to be safe...
	return 0;
	}

sub asd_del_arr {
	my $self = shift;
	my $sid = shift;
	# get the other arr...
	my $id = ($sid =~ /\D/) ? $self->{scoop}->get_story_id_from_sid($sid) : $self->{scoop}->get_sid_from_story_id($sid);
	$self->cache->remove("asd_arr_$sid");
	#$self->cache->stamp("asd_arr_$sid");
	$self->cache->remove("asd_arr_$id");
	#$self->cache->stamp("asd_arr_$id");
	undef $self->{ASDA}->{"$sid"};
	undef $self->{ASDA}->{"$id"};
	return;
	}

1;
