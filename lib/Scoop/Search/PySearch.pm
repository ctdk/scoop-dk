package Scoop;
use strict;

use HTTP::Request;
use HTTP::Request::Common;
use LWP::UserAgent;
use DateTime;
use Digest::MD5;

# functions to integrate the mod_python search stuff into Scoop. Yay!

sub pysearch_post {
	my $S = shift;
	my $args = shift;
	my $surl = $S->{UI}->{VARS}->{pysearch_url};
	my $ua = LWP::UserAgent->new;
	# can't have folks ruthlessly hitting the search functions
	my $sthrot = $S->{UI}->{VARS}->{search_throttle_time} || 5;
	my $rip = $S->{REMOTE_IP};
	my $now = time();
	$S->cache->store("sthrottle_$rip", $now, "+60s");

	my $res = $ua->request(POST $surl, [ query => $args->{query}, division => $args->{division}, max => $args->{max}, sortby => $args->{sortby}, wayback => $args->{wayback}, wayfront => $args->{wayfront}, offset => $args->{offset}, uid => $S->{UID} ]);
	$S->cache->store("sthrottle_$rip", time(), "+${sthrot}s");

	return $res;

	}

sub pysearch_parse {
	my $S = shift;
	my $args = shift;
	my $results = shift;
	# Let's get ready to RUMBLE!!!!
	# testing - basic formatting
	# ??
	my @rarr = split(/\n/, $results);
	my $resret;
	my $olstart = $args->{offset} + 1;
	my $resdump = qq|<table align="center" width=100% cellspacing=0 cellpadding=5 border=1 style="border: 1px solid gray; border-collapse: collapse"><tr bgcolor="#f0f0f0" align="center"><td>Result</td><td>Story</td><td>Author</td><td>Date</td><td>Comments</td><td>Recs</td><td>Impact</td></tr>|;
	my $numhit;
	my $searchtime;
	my $runtime;
	my $rnum;
	my $dnum = $args->{offset} || 0;
	my $dupchk = {};
	foreach my $k (@rarr){
		last if $k eq '.';
		# figure out if we're doing headers
		if($k =~ /^#/){
			# clean up a little
			$k =~ s/^# //;
			my ($head, $val) = split(/:/, $k);
			# getting out of here ought to work.
			next if !$val;
			if ($head =~ /^Number/){
				$numhit = $val;
				}
			elsif ($head =~ /^Search/){
				$searchtime = $val;
				}
			elsif ($head =~ /^Run/){
				$runtime = $val;
				}
			next;
			}
		# what the line's made up of:
		# nrec,ncomment,impact,sid,author,title,date
		# Error handling!
		if($k =~ /^\D/){
			# if we're still here, and we have a line that doesn't
			# start with a number, we have an error.
			($numhit, $rnum, $searchtime, $runtime) = 0;
			$resdump = "Error! $k<br />\n";
			last;
			}
		my @line = split(/\t/, $k);
		# we may wish to grab some other info, like new comments,
		# at a later date.
		$line[2] /= 1000.0;
		$line[2] = sprintf("%.3f", $line[2]);
		# and check for dupes
		if ($dupchk->{$line[3]}){
			$args->{offset} += 1;
			next;
			}
		$dupchk->{$line[3]} = 1;
		$rnum++; $dnum++;
		# format the date
		# get our timezone
		my $tz = $S->pref('time_zone');
		#my $tzoff = tz_offset($tz);
		# coming from epoch, format according to the user's time zone
		#$line[6] = gmtime($line[6]);
		#my $dt = DateTime->from_epoch( epoch => $line[6]);
		my $tzoff = &Time::Timezone::tz_offset(lc($tz));
		#chomp $tzoff;
		#$dt->set_time_zone($tzoff);
		#$line[6] = $dt->ymd('/') . " " . $dt->hms . " $tz";
		$line[6] += $tzoff;
		#warn "line[6]: $line[6]\n";
		my ($year,$month,$day,$hour,$min,$sec);
		eval {
		($year,$month,$day,$hour,$min,$sec) = Date::Calc::Time_to_Date($line[6]);
			};
		$line[6] = sprintf("%02d/%02d/%02d %02d:%02d:%02d $tz", $month, $day, $year, $hour, $min, $sec);
		$line[0] = '*' if $line[0] == 83; 
		my $urlpre = ($line[3] !~ /dailykos.net/) ? "/storyonly/" : '';
		$resdump .= qq|
			<tr><td>$dnum</td><td><a href="${urlpre}$line[3]">$line[5]</a></td><td><a href="/user/$line[4]">$line[4]</a></td><td>$line[6]</td>
			<td>$line[1]</td><td>$line[0]</td><td>$line[2]</td>
			</tr>
			|;
		}
	$resdump .= "</table>" if $resdump !~ /^Error/;
	# Need to send the search args in, it seems
	$resret = "<p>Found $numhit results, displaying $rnum. Search time $searchtime, run time $runtime.</p>" . $resdump;
	return ($resret, $numhit);
	}

sub pysearch_comment_post {
	my $S = shift;
	my $args = shift;
	my $surl = $S->{UI}->{VARS}->{pysearch_comment_url};
	# should only need this for comments, really
	#my $uri = $S->apache->uri();
	my $uri;
	foreach (sort keys %{$args}){
		$uri .= "$_$args->{$_}";
		}
	my $sc = Digest::MD5::md5_hex($uri);
	my $cres = $S->cache->fetch("search_$sc");
	return $cres if($cres);

        my $ua = LWP::UserAgent->new;
	# can't have folks ruthlessly hitting the search functions
        my $sthrot = $S->{UI}->{VARS}->{search_throttle_time} || 5;
        my $rip = $S->{REMOTE_IP};
        my $now = time();
        $S->cache->store("sthrottle_$rip", $now, "+60s");

	my $res = $ua->request(POST $surl, [ query => $args->{query}, max => $args->{max}, offset => $args->{offset}, sortby => $args->{sortby}, wayback =>
$args->{wayback}, wayfront => $args->{wayfront}, uid => $S->{UID} ]);
	$S->cache->store("sthrottle_$rip", time(), "+${sthrot}s");
	$S->cache->store("search_$sc", $res, "+60s");
	return $res;
	}

sub py_comment_search_parse {
	my $S = shift;
	my $args = shift;
	my $results = shift;

	# the comment results are different enough than the story results
	# that we're going to want to parse them separately.

	# this is what it sends back for comments, in each row. The other stuff
	# is similar to the story/diary search
	# sid - cid - pid - points (avg) - awards (numrate) - nickname -
	#   recrank - trollrank - uid - subject - tepoch

	# start parsing stuff out
	my @rarr = split(/\n/, $results);
	# For obvious reasons, this function's very similar to pysearch_parse
	my $resret;
        my $olstart = $args->{offset} + 1;
	my $resdump = qq|<table align="center" width=100% cellspacing=0 cellpadding=5 border=1 style="border: 1px solid gray; border-collapse: collapse"><tr bgcolor="#f0f0f0" align="center"><td>Result</td><td>Comment</td><td>Author</td><td>Date</td><td>Recommends</td><td>Troll Ratings</td></tr>|;
        my $numhit;
        my $searchtime;
        my $runtime;
        my $rnum;
        my $dnum = $args->{offset} || 0;
        my $dupchk = {};

	foreach my $k (@rarr){
                last if $k eq '.';
                # figure out if we're doing headers
                if($k =~ /^#/){
                        # clean up a little
                        $k =~ s/^# //;
                        my ($head, $val) = split(/:/, $k);
                        # getting out of here ought to work.
                        next if !$val;
                        if ($head =~ /^Number/){
                                $numhit = $val;
                                }
                        elsif ($head =~ /^Search/){
                                $searchtime = $val;
                                }
                        elsif ($head =~ /^Run/){
                                $runtime = $val;
                                }
                        next;
                        }
		# Error handling!
                if($k =~ /^\D/){
                        # if we're still here, and we have a line that doesn't
                        # start with a number, we have an error.
                        ($numhit, $rnum, $searchtime, $runtime) = 0;
                        $resdump = "Error! $k<br />\n";
                        last;
                        }
		my @line = split(/\t/, $k);
                # we may wish to grab some other info, like new comments,
                # at a later date.
                $line[3] /= 100.0;
                $line[3] = sprintf("%.2f", $line[3]);
                # and check for dupes
                if ($dupchk->{"$line[0]-$line[1]"}){
                        $args->{offset} += 1;
                        next;
                        }
		if(!$S->have_perm('zero_rate') || !$args->{hidden_comments}){
			next if $line[3] < 1 && ($line[6] != 0);
			}
                $dupchk->{"$line[0]-$line[1]"} = 1;
                $rnum++; $dnum++;
                # format the date
                # get our timezone
                my $tz = $S->pref('time_zone');
                # coming from epoch, format according to the user's time zone
                my $tzoff = &Time::Timezone::tz_offset(lc($tz));
                $line[10] += $tzoff;
                my ($year,$month,$day,$hour,$min,$sec) = Date::Calc::Time_to_Date($line[10]);
                $line[10] = sprintf("%02d/%02d/%02d %02d:%02d $tz", $month,
$day, $year, $hour, $min, $sec);
                $resdump .= qq|
                        <tr><td>$dnum</td><td><a href="/comments/$line[0]/$line[1]#c$line[1]">$line[9]</a></td><td><a href="/user/$line[7]">$line[7]</a></td><td>$line[10]</td>
                        <td>$line[5]</td><td>$line[6]</td>
                        </tr>
                        |;
                }
        $resdump .= "</table>" if $resdump !~ /^Error/;
        # Need to send the search args in, it seems
        $resret = "<p>Found $numhit results, displaying $rnum. Search time $searchtime, run time $runtime.</p>" . $resdump;
        return ($resret, $numhit);
	}

1;
