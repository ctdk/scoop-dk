package Scoop;
use strict;
my $DEBUG = 0;

=head1 Scoop::DB::SlaveUtils.pm

Some db functions that are specific to a master/slave DB setup.

=over 4

=item *
raise_slave_to_master()

In the event that the master db dies, raise a slave to be the new master. B<***NOTE***> Does not actually do so yet -- since raising a slave to be master within Scoop is not operational yet, this just kills Scoop with an error message for now.

=cut

sub raise_slave_to_master {
	my $S = shift;
	# for now...
	die "*** The Master DB seems to have died, and unfortunately, Scoop can't raise a slave to be master at the moment. Bailing.\n";

	}

=pod

=item *
get_dbh

Not specifically restricted to a master/slave db. However, if Scoop is not running on a master/slave setup, it just returns the standard $S->{DBH}. If it is, it will check to make sure the master is still up and running. If it is, it will return the master db handle. Otherwise, it will raise a slave to master and adjust the slaves as necessary. Also, if you pass a true value to the function, it will pick between the master and the pool of slaves and return one of their db handles. This is really only useful when coming from db_select, since the slaves cannot do inserts or updates.

=cut

sub get_dbh {
	my $S = shift;
	my $select = shift;
	my $dbh;

	# The *absolute* first thing to do is see if we're even using slaves.
	# hmm?
	if(!$S->{HAVE_SLAVE}){
		$dbh = $S->{DBH};
		# and break out now - no need to go further
		$dbh->do("use $S->{CONFIG}->{db_name}");
		return $dbh;
		}
	# next see if we're doing a select. If not, check and make sure the
	# main db's alive and we don't need to raise a slave
	elsif(!$select){
		$dbh = $S->{DBH};
		warn "Using master db\n" if $DEBUG;
		}
	else { # we are doing a select
		# pick a dbh, any dbh
		my $j = int(rand($S->{NUMSLAVES} + 1));
		if($j){
			my $s = int(rand($S->{NUMSLAVES}));
			$dbh = $S->{SLAVEDB}->[$s];
			warn "Using slave db $s\n" if $DEBUG;
			eval { $dbh->ping };
			# hopefully this works
			if($@){
				warn "Slave went away hard, trying to use master: $@\n";
				$dbh = $S->get_dbh();
				}
			}
		else {
			$dbh = $S->get_dbh();
			}	
		}
	$dbh->do("use $S->{CONFIG}->{db_name}");
	return $dbh;
	}

=pod

=item *
get_archive_dbh {

Very similar to get_dbh, but for the archive db, in case you have a slave set up for the archive database. B<***NOTE***> Slave dbs are not supported yet for the archive. At this time, it will just return a handle to the main archive db.

=cut

sub get_archive_dbh {
	my $S = shift;
	my $select = shift;
	# we'll fix this to be better later.
	my $dbh;
	if(!$S->{HAVE_SLAVE}){
		$dbh = $S->{DBH}; #$S->{DBHARCHIVE};
		}
	# this really ought not happen...
	elsif(!$select){
		$dbh = $S->{DBH};
		}
	else {
		my $j = int(rand($S->{NUMSLAVES} + 1));
                if($j){
                        my $s = int(rand($S->{NUMSLAVES}));
                        $dbh = $S->{SLAVEDB}->[$s];
                        warn "Using slave db $s\n" if $DEBUG;
                        eval { $dbh->ping };
                        # hopefully this works
                        if($@){
                                warn "Slave went away hard, trying to use master: $@\n";
                                $dbh = $S->get_dbh();
                                }
                        }
                else {
                        $dbh = $S->get_dbh();
                        }
		}
	$dbh->do("use $S->{CONFIG}->{db_name_archive}");
	return $dbh;

	}


1;
