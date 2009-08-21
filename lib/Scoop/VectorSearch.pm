package Scoop;
use strict;
use Digest::MD5 qw(md5);

=pod

=head1 VectorSearch.pm

This file contains the functions for using the java vector search engine, which will hopefully provide a better working alternative to the default search for high traffic sites.

Before trying to use these funtions, make sure you read the documentation for the VectorSpace server.

=head1 AUTHOR

Jeremy Bingham B<jeremy@satanosphere.com>

=head1 FUNCTIONS

Summaries of the functions that are likely to be used outside of this module. If they aren't in the pod, they aren't likely to be terribly useful elsewhere.

=cut

=over 4

=item *
vector_search

Takes search terms, searches for them, parses them out into a Scoop-friendly format, and sends them on back.

=cut

sub vector_search {
	my $S = shift;
	my $searchtype = shift;
	my $terms = shift;
	my $section = shift;
	my $num = shift;
	my $offset = shift;
	
	my $siteid = $S->{UI}->{VARS}->{'vsid'};
	my @words = split / /, $terms;
	my $namespace = $siteid . "-$searchtype";
	# just to be safe, make sure it's not a diary.
	$namespace .= ($section && $section ne 'Diary') ? "-$section" : '';

        my $sock = $S->v_connect();
        return "Connection failed!" if(!$sock);
	my $searchid = 1;	
	my $searchref = {};
	my $warnings; # for any warnings that might come up.
	$warnings = ($#words > 10) ? "Searches limited to 10 words or less" : '';

	for(my $i = 0; $i < 10; $i++){
		my $searchstr = "$namespace $words[$i]";
		$S->v_write_socket($sock, $searchid, 1, 0, $searchstr);
		my ($id, $type, $length, $flags, $response) = $S->v_read_socket($sock);
		# We have our response, now we need to process it.
		$searchid++;
		next if($response eq '.');
		$searchref->{$words[$i]} = $S->v_search_process($response);
		
		}
        # close our socket
        $S->v_sock_close($sock);

	return 0 if(!%$searchref);

	# Merge the results
	my $merged = $S->v_merge_results($searchref);
	
	# and send them back to the main search function
	return $merged;

	}

# sigh... The _determine_search_q function is nasty enough, I'm going to just
# bypass it totally if we're using the vector space search. *This* is the 
# function that actually gets called by Search.pm

sub v_determine_query {
	my $S = shift;
	my $args = shift;

	my $results = $S->vector_search($args->{type}, $args->{string}, $args->{section});
	my $sids;
	
	if(!$results) {
		$sids = "sid = NULL";
		return $sids;
		}
	foreach my $sid(sort { $results->{$b} <=> $results->{$a} } keys %$results){
		if($args->{type} eq 'story' || $args->{type} eq 'diary'){
			$sids .= ", '$sid'";
			#$sids =~ s/^,//;
			#$sids = "sid IN ($sids)";
			}
		else {
			my ($ssid, $cid) = split /=/, $sid;
			$sids .= "OR (c1.sid = '$ssid' AND c1.cid = '$cid') ";
			$sids =~ s/^OR//;
			}
		}

	if($args->{type} eq 'story' || $args->{type} eq 'diary'){
		$sids =~ s/^,//;
		$sids = "sid IN ($sids)";
		}
	
	return $sids;

	}

sub v_sock_open {
	my $S = shift;

	my $v_host = shift || $S->{UI}->{VARS}->{'vector_search_host'} || '127.0.0.1';
	my $v_port = shift || $S->{UI}->{VARS}->{'vector_search_port'} || 4662;

	my $sock = $S->connect_remote($v_host, $v_port);

	return $sock;

	}

sub v_sock_close {
	my $S = shift;
	my $sock = shift;

	$S->close_remote($sock);
	return;

	}

=item *
v_index_story

Run as a hook when a story is posted. Indexes the story's content.

=cut

sub v_index_story {
	my $S = shift;
	my $hook = shift;
	my $sid = shift;
	my $title = shift;
	my $intro = shift;
	my $body = shift;
	my $section = shift;
	
	return if(!$S->{UI}->{VARS}->{'use_vector_search'});

	# Need to get ourselves connected and authenticated first
	my $sock = $S->v_connect();
	return "Connection failed!" if(!$sock);

	# get the story to be indexed formatted properly
	my $sendstr = $S->v_index_story_format($sid, $title, $intro, $body, $section);
	# and send it
	$S->v_write_socket($sock, 1, 0, 0, $sendstr);
	my ($id, $type, $flags, $length, $response) = $S->v_read_socket($sock);
	# do it again without the section if this isn't a diary.
	if($section ne 'Diary'){
		$sendstr = $S->v_index_story_format($sid, $title, $intro, $body);
        	# and send it
        	$S->v_write_socket($sock, 1, 0, 0, $sendstr);
        	($id, $type, $flags, $length, $response) = $S->v_read_socket($sock);

		}

	$S->v_sock_close($sock);
	return $response;

	}

=item *
v_index_comment

Run as a hook when a comment is posted. Indexes the comment's content.

=cut

sub v_index_comment {
	my $S = shift;
	my $hook = shift;
	my $sid = shift;
	my $cid = shift;
	my $subject = shift;
	my $comment = shift;

	return if(!$S->{UI}->{VARS}->{'use_vector_search'});

        # Need to get ourselves connected and authenticated first
        my $sock = $S->v_connect();
        return "Connection failed!" if(!$sock);

        # get the comment to be indexed formatted properly
        my $sendstr = $S->v_index_comment_format($sid, $cid, $subject, $comment);
        # and send it
        $S->v_write_socket($sock, 1, 0, 0, $sendstr);
        my ($id, $type, $flags, $length, $response) = $S->v_read_socket($sock);
	$S->v_sock_close($sock);
        return $response;

	}

sub v_quote_sid {
	my $S = shift;
	my $sid = shift;

	$sid =~ s#/#-#g;
	return $sid;
	}

sub v_unquote_sid {
	my $S = shift;
	my $sid = shift;

	$sid =~ s#-#/#g;
	return $sid;
	}

sub v_search_process {
	my $S = shift;
	my $response = shift;

	my @results = split /\n/, $response;
	my $shashref = {};
	foreach my $result (@results){
		my ($nspace, $r) = split /\//, $result;
		my ($rsid, $weight) = split /:/, $r;
		# if we're doing a comment search, we've gotta split the cid off
		#my($ssid, $scid) = split /=/, $rsid;
		my $ssid = $S->v_unquote_sid($rsid);
		# k, we have everything split apart now. Create a hashref to store
		# these values in for easier shuffling around.
		# might need to adjust this later
		#my $k = ($scid) ? $ssid . "/$scid" : $ssid; 
		$shashref->{$ssid} = $weight;

		}
	# it's in a usable form now, send it back.
	return $shashref;
	}

sub v_merge_results {
	my $S = shift;
	my $results = shift;

	my $merged = {};
	foreach my $word (keys %$results){
		my $sidref = $results->{$word};
		#foreach my $sid (keys %$results->{$word}){
		foreach my $sid (keys %$sidref){
			# if we've already come across this sid, increase
			# the sid's weight
			my $combweight = $merged->{$sid} + $results->{$word}->{$sid};
			$merged->{$sid} = $combweight;

			}
		}

	# We've got a hashref of sid's sorted by weight now.
	return $merged;
	}

sub v_write_socket {

	my $S = shift;
	my $sock = shift;
	my $id = shift;
	my $type = shift;
	my $flags = shift;
	my $sendstr = shift;
	my @ary = ($id, $type, $flags, length($sendstr));

	my $packstr = pack 'N4', @ary;

	send $sock, $packstr . $sendstr, 0;
	
	}

sub v_read_socket {

	my $S = shift;
	my $sock = shift;
	my ($headers, $message);
	recv $sock, $headers, 16, 0;
	my ($id, $type, $flags, $length) = unpack("N4", $headers);
	recv $sock, $message, $length, 0;
	return ($id, $type, $flags, $length, $message); 

	}

# authorize ourselves to the vs server
sub v_auth {
	my $S = shift;
	my $sock = shift;
	my $user = shift || $S->{UI}->{VARS}->{'vector_user'};
	my $pass = shift || $S->{UI}->{VARS}->{'vector_pass'};
	
	my ($id, $type, $flags, $length, $response) = $S->v_read_socket($sock);
	$S->v_write_socket($sock, 0, 0, 0, $user);
	($id, $type, $flags, $length, $response) = $S->v_read_socket($sock);
	my $enc = md5($pass . $response);
	$S->v_write_socket($sock, 0, 0, 0, $enc);
	($id, $type, $flags, $length, $response) = $S->v_read_socket($sock);
	return $response;

	}

# set up a complete connection with the server, including all authentication,
# and return a socket filehandle

sub v_connect {
	my $S = shift;

	my $sock = $S->v_sock_open();
	my $response = $S->v_auth($sock);
	return 0 if ($response ne 'AUTH OK');
	return $sock;
	}

# format input for indexing stories

sub v_index_story_format {
	my $S = shift;
	my $sid = shift;
	my $title = shift;
	my $intro = shift;
	my $body = shift;
	my $section = shift;

	# Looks like some quotes are creeping in somehow
	$section =~ s/'//g;

	# set the namespace name first
	my $namespace;
	if(!$section){
		$namespace = $S->{UI}->{VARS}->{vsid} . "-story";
		}
	elsif($section eq 'Diary') {
		$namespace = $S->{UI}->{VARS}->{vsid} . "-diary";
		}
	else {
		$namespace = $S->{UI}->{VARS}->{vsid} . "-story-$section";
		}

	# and quote the sid
	my $vdoc = $S->v_quote_sid($sid);

	# and join all the text together. taking out any newlines or
	# carriage returns probably wouldn't be a bad idea.
	my $vtext = $title . " " . $intro . " " . $body;
	$vtext =~ s/\n//g;
	$vtext =~ s/\r//g;

	# return them in a convenient string

	return("$namespace $vdoc $vtext");

	}

# format input for indexing comments

sub v_index_comment_format {
        my $S = shift;
        my $sid = shift;
	my $cid = shift;
        my $title = shift;
        my $comment = shift;

        # set the namespace name first
        my $namespace = $S->{UI}->{VARS}->{vsid} . "-comment";

        # and quote the sid
        my $vdoc = $S->v_quote_sid($sid);
	# stick the cid onto the end of the sid in an easily splittable way
	$vdoc .= "=$cid";

        # and join all the text together. taking out any newlines or
        # carriage returns probably wouldn't be a bad idea.
        my $vtext = $title . " " . $comment;
        $vtext =~ s/\n//g;
        $vtext =~ s/\r//g;

        # return them in a convenient string

        return("$namespace $vdoc $vtext");

        }


=head1 BUGS

Be certain of them. Also look in the Vector Space docs.

=cut

1;
