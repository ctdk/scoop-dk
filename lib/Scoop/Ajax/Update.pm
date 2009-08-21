package Scoop;
use strict;
my $DEBUG = 0;

sub ajax_update {
        my $S = shift;

        my $mode = $S->{CGI}->param('mode');
        my $sid = $S->{CGI}->param('sid');
        my $caller_op = $S->cgi->param('caller_op');
	# update specific params
	my $detail = $S->cgi->param('detail');
	my $serial = $S->cgi->param('serial');
	my $cid = $S->cgi->param('cid'); # hopefully won't collide
					 # with anything down the line
	my $comment_id = $S->cgi->param('comment_id');
	my $id = $S->cgi->param('id') || $S->get_story_id_from_sid($sid);
	if($detail eq 'c'){
		# things are a little different.
		$S->{CURRENT_TEMPLATE} = 'updatec_template';
		# hmph.
		my $rating_limit;
		if($S->{UI}->{VARS}->{limit_comment_rating_period}){
             		$rating_limit = "((UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(date)) / 3600) as hoursposted,";
             		}
		else {
			$rating_limit = "NULL as hoursposted,",
			}
		my $date_format = $S->date_format('date');
		my $short_date = $S->date_format('date', 'short');
		my $qsid = $S->dbh->quote($sid);
		my $qid = $S->dbh->quote($id);
		my $qc = $S->dbh->quote($cid);
		my $qc_id = $S->dbh->quote($comment_id);
		my $where = ($comment_id) ? "id = $qc_id" : qq|story_id = $id and cid = $qc|;
		my ($rv, $sth) = $S->db_select({
			DEBUG => 0,
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT => qq|sid, cid, pid, $date_format as f_date, $short_date as mini_date, $rating_limit subject, comment, uid, points, lastmod AS numrate, points IN (NULL) AS norate, pending, sig_status, sig, commentip, recrate, trollrate, raters, id, story_id|,
			FROM => 'comments',
			WHERE => $where
			});
		my $comment = $sth->fetchrow_arrayref;
		$sth->finish;
		my $ucomment = $S->format_comment($comment);
		#my $ucomment = $S->display_comments($sid, $pid, 'alone', $cid);
		# hopefully this works...
		$S->{UI}->{BLOCKS}->{CONTENT} = $ucomment;
		return;
		}
        # if $sid doesn't actually exist, redirect back to the fp.
        if(!$sid){
            my $redir = $S->{UI}->{VARS}->{site_url} . "/";
            $S->{APACHE}->headers_out->{'Location'} = $redir;
            $S->{HEADERS_ONLY}=1;
            }
	# try looking for the cache here
	my $ser = $S->check_serial($sid);
	if ($ser == $serial && $serial ne ''){
		$S->ajax_success();
		return;
		}
	# if we're here, check to see if there's a current cached version		# to return.
	my $tocache = undef;
	if($S->{UI}->{VARS}->{use_static_update_pages} && (!$S->have_perm('story_admin'))){ # || !$S->have_perm('zero_rate'))){
		my $ucfile = $S->get_update_file_path($sid, $detail, $ser);	
		# check if the file exists
		if (-e $ucfile){
			# we're going to want to return the cached version
			# of this page
			$S->{UI}->{BLOCKS}->{'__stat_page__'} = $S->get_update_static($ucfile);
			# this *should* do it
			if($S->{UI}->{BLOCKS}->{'__stat_page__'} ){
				$S->{CURRENT_TEMPLATE} = '__stat_page__';
				return;
				}
			else {
				# something went wrong...
				warn "getting static update page failed\n";
				# don't try caching it again for now
				}
			}
		else {  # we're going to want to cache this file
			# can't really do that from here, though, so we set
			# a flag that we should do so later.
			$tocache = 1;
			}
		}

        my $comments;

        #$S->{UI}->{BLOCKS}->{STORY} = qq|
        #       <TABLE CELLPADDING=0 CELLSPACING=0 BORDER=0 width="100%">|;
        #$S->{UI}->{BLOCKS}->{COMMENTS} = qq|
        #       <TABLE CELLPADDING=0 CELLSPACING=0 BORDER=0 width="100%">|;

        # Filter this through get_sids for perms
	my $sids = $S->get_story_ids({'id' => $id});
	$id = $sids->[0];
        $sids = $S->get_sids({'id' => $id});
        $sid = $sids->[0];

        my ($story_data, $story) = $S->displaystory($id);

        my $checkstory = $S->_check_for_story($sid);

        my $commentstatus = $S->_check_commentstatus($sid);

        # Run a hook here to do any processing we need to do on a story
        # before we display it.
	# shouldn't be necessary for this
        #$S->run_hook('story_view', $sid, $story_data);

        unless ($checkstory && $story_data && $story) {
                $S->{UI}->{BLOCKS}->{STORY} .= qq|
                        <table cellpadding="0" cellspacing="0" border="0" width="100%">
                                <tr><td>%%norm_font%%<b>Sorry. I can\'t seem to find that story.</b>%%norm_font_end%%</td></tr>
                        </table>|;

                return;
        }


        $S->{UI}->{BLOCKS}->{STORY} .= $story;
        if ($story_data->[11] == -2) {
                $mode = 'moderate';
        }

        if ($story_data->[11] <= -2 && $story_data->[11] > -4) {
                if (!$S->have_perm('moderate')) {
                        $S->{UI}->{BLOCKS}->{STORY} = qq|
                        <table width="100%" border="0" cellpadding="0" cellspacing="0">
                        <tr bgcolor="%%title_bgcolor%%">
                                <td>%%title_font%%Permission Denied.%%title_font_end%%</td>
                        </tr>
                        <tr><tr>%%norm_font%%Sorry, but you can only moderate stories if you have a valid user account.
                        Luckily for you, making one is easy! Just <a HREF="%%rootdir%%/newuser">go here</a> to get started.
                        %%norm_font_end%%</td></tr>
                        </table>|;
                        return;
                }

                my $message = $S->_story_mod_write($sid);
                if ($message) {
                        $S->{UI}->{BLOCKS}->{STORY} .= qq|<table width="100%" border=0 cellpadding=0 cellspacing=0><tr><td>%%norm_font%%$message %%norm_font_end%%</td></tr></table>|;
                        $S->{UI}->{BLOCKS}->{STORY} .= '<P>';
                }
                my ($which, $mod_stuff) = $S->story_mod_display($sid);
                my $author_control = $S->author_control_display($story_data);
                warn "Author block is:\n$author_control\n" if $DEBUG;

                $S->{UI}->{BLOCKS}->{STORY} .= $author_control;

                if ($which eq 'content') {
                        $S->{UI}->{BLOCKS}->{STORY} .= $mod_stuff if ($story_data->[2] ne $S->{UID});
                } else {
                        $S->{UI}->{BLOCKS}->{BOXES} .= $mod_stuff;
                        $S->{UI}->{BLOCKS}->{BOXES} .= $mod_stuff;
                }
        }

        $comments = $S->display_comments($sid, '0') unless $commentstatus == -1 || $caller_op eq 'storyonly'; # || $S->pref('commentDisplayMode') eq 'hide';
        # grumbles grumble but they don't fall down.
        if($comments || $S->pref('commentDisplayMode') ne 'hide'){
                #my $bar = $S->run_box('comment_controls',1);
                #$comments .= $bar;
                $comments = $S->{UI}->{BLOCKS}->{comment_div_start} . $comments . $S->{UI}->{BLOCKS}->{comment_div_end};
                }
        #$S->update_seen_if_needed($sid) unless $caller_op eq 'storyonly' || $S->pref('commentDisplayMode') eq 'hide';# unless ($S->{UI}->{VARS}->{use_static_pages});

        $S->{UI}->{BLOCKS}->{STORY} .= $S->story_nav($sid);
        #$S->{UI}->{BLOCKS}->{STORY} .= '<TR><TD>&nbsp;</TD></TR>';

        $S->{UI}->{BLOCKS}->{COMMENTS} .= $S->comment_controls($sid, 'top');
        $S->{UI}->{BLOCKS}->{COMMENTS} .= qq|$comments|;

        if ($comments) {
                $S->{UI}->{BLOCKS}->{COMMENTS} .= $S->comment_controls($sid, 'top');
        }

        #$S->{UI}->{BLOCKS}->{STORY} .= '</TABLE>';
        #$S->{UI}->{BLOCKS}->{COMMENTS} .= '</TABLE>';

        $S->{UI}->{BLOCKS}->{subtitle} .= $story_data->[3] || $S->{UI}->{BLOCKS}->{slogan};
        $S->{UI}->{BLOCKS}->{subtitle} =~ s/</&lt;/g;
        $S->{UI}->{BLOCKS}->{subtitle} =~ s/>/&gt;/g;

	# if we're going to make a cached file, do so here.
	if($tocache){
		$S->write_update_static($sid, $detail, $ser);
		}

        return;

	}

sub make_update_path {
	my $S = shift;
	my $path = shift;
	# stealing from make_cache_dir_path
	$path =~ s/^$S->{UI}->{VARS}->{update_page_path}\///;
	my $pre_path = $S->{UI}->{VARS}->{update_page_path};
	my @elem = split '/', $path;
        pop @elem;

        foreach my $dir (@elem) {
                $pre_path .= '/'.$dir;
                unless (-d $pre_path) {
                        warn "Making directory $pre_path\n" if $DEBUG;
                        mkdir ($pre_path, 0755) || warn "Can't create directory
$pre_path: $!\n";
                	}
        	}

	}

sub get_update_file_path {
	my $S = shift;
	my $sid = shift;
	my $detail = shift;
	my $serial = shift;

	my $trustlev;
	if(!$S->have_perm('comment_post')){
		$trustlev = 'anon';
		}
	elsif ($S->have_perm('zero_rate')){
		$trustlev = 'tu';
		}
	else {
		$trustlev = 'normal';
		}
	my $trlinate;
	if($S->have_perm('zero_rate')){
		$trlinate = $S->trl_chk($S->{UID});
		$trlinate = "_trl$trlinate";
		}
	my $order = $S->get_comment_option('commentorder');
	my $rating = $S->get_comment_option('commentrating');
	# simple enough, really. Just make the expected path for the file
	# we want and return it.
	my $bp = $S->{UI}->{VARS}->{update_page_path};
	my $uc = $bp . "/" . $sid . "_d${detail}_s${serial}_${trustlev}_${order}_$rating$trlinate";
	$uc =~ s/ //g;
	return $uc;
	}

sub get_update_static {
	# borrowing a lot of stuff from Static.pm in much of this file
	my $S = shift;
	my $file = shift;
	unless (-e $file && -r $file) {
                warn "Static file <$file> does not exist, or isn't readable.\n" if $DEBUG;
                return undef;
        	}
	open FH, "<$file" || { warn "Can't open $file: $!\n" and return undef };
	my @file_info = stat FH;
	my $stat_file; # keep the old way, I suppose
	{ local $/; $stat_file = <FH> }
	close FH;
	return $stat_file;
	}

sub write_update_static {
	my $S = shift;
	my $sid = shift;
	my $detail = shift;
	my $serial = shift;
        my $trustlev;
        if(!$S->have_perm('comment_post')){
                $trustlev = 'anon';
                }
        elsif ($S->have_perm('zero_rate')){
                $trustlev = 'tu';
                }
        else {
                $trustlev = 'normal';
                }

        my $order = $S->get_comment_option('commentorder');
        my $rating = $S->get_comment_option('commentrating');
        my $bp = $S->{UI}->{VARS}->{update_page_path};
        my $uc = $bp . "/" . $sid . "_d${detail}_s${serial}_${trustlev}_${order}_$rating";
	$uc =~ s/ //g;
	#warn "$S->{NICK} $detail $serial $uc\n";
	
	# make sure this version of the file doesn't already exist and was
	# created by someone else between when we decided we wanted to cache
	# the file and actually doing so. Hopefully this will eliminate the
	# shearing problem.
	return if -e $uc;
	$S->make_update_path($uc); # make sure the path we want to write is
				   # there
	# borrowing a $page from Static.pm
	my $page = $S->{UI}->{BLOCKS}->{$S->{CURRENT_TEMPLATE}};
        $page =~ s/%%STORY%%/$S->{UI}->{BLOCKS}->{STORY}/g;
        $page =~ s/%%COMMENTS%%/$S->{UI}->{BLOCKS}->{COMMENTS}/g;
        $page =~ s/%%CONTENT%%/$S->{UI}->{BLOCKS}->{CONTENT}/g;
	$page =~ s/%%subtitle%%/$S->{UI}->{BLOCKS}->{subtitle}/g;
	open FH, ">$uc" || { warn "Can't open $uc for writing: $!\n" and return undef };
	print FH $page || warn "Can't write to $uc: $!\n";
	close FH;
	return 1;
	}

sub check_serial {
	my $S = shift;
	my $sid = shift;

	# for now, we just pull from the db automatically.
	if( my $cached = $S->cache->fetch('serial_'.$sid) ){
		warn "Returning cached serial...\n" if $DEBUG;
		}
	my ($rv, $sth) = $S->db_select({
		WHAT => 'serial',
		FROM => 'story_trigger',
		WHERE => "sid = '$sid'"
		});
	my $r = $sth->fetchrow();
	$sth->finish;
	# hack to set up the trigger row for stories that haven't had it
	# created yet.
	if($rv == 0){
		($rv, $sth) = $S->db_insert({
			INTO => 'story_trigger',
			COLS => 'sid, updated',
			VALUES => "'$sid', NOW()"
			});
		$sth->finish;
		$r = 0; # best be safe
		}
	# and if we're here, stick it in the cache
	$S->cache->store('serial_'.$sid, $r);
	return $r;
	}

sub update_serial {
	my $S = shift;
	my $sid = shift;
	my $minor = shift;
	my ($rv, $sth);
	if($minor){
		($rv, $sth) = $S->db_select({
			WHAT => 'unix_timestamp(now()) - unix_timestamp(updated) as last_updated',
			FROM => 'story_trigger',
			WHERE => "sid = '$sid'"
			});
		my $diff = $sth->fetchrow;
		$sth->finish;
		my $set = ($diff < $S->{UI}->{VARS}->{minor_update_time}) ?
			'ismodified = 1' :
			'serial = serial + 1, ismodified = 0, updated = NOW()';
		# do the transactions!
		($rv, $sth) = $S->db_start_transaction();
		($rv, $sth) = $S->db_update({
			WHAT => 'story_trigger',
			SET => $set,
			WHERE => "sid = '$sid'"
			});
		# and make sure we're OK
		($rv, $sth) = $S->db_select({
			WHAT => 'serial',
			FROM => 'story_trigger',
			WHERE => "sid = '$sid'"
			});
		my $chkser = $sth->fetchrow();
		# do we rollback, or not?
		# FIXME: don't forget to update the cached values of these
		# too at some point
		$S->db_commit();
		$S->cache->stamp('serial_'.$sid);
		$S->cache->store('serial_'.$sid, $chkser);
		return $chkser; # good for now, I guess
		}
	# otherwise, we're doing a major update. Strangely, that's actually		# easier than the minor update
	($rv, $sth) = $S->db_start_transaction();
	($rv, $sth) = $S->db_update({
		WHAT => 'story_trigger',
		SET => 'serial = serial + 1, ismodified = 0, updated = NOW()',
		WHERE => "sid = '$sid'"
		});
	($rv, $sth) = $S->db_select({
                WHAT => 'serial',
                FROM => 'story_trigger',
                WHERE => "sid = '$sid'"
                });
	my $chkser = $sth->fetchrow();
        $S->db_commit();
	# if we're here, I guess all is updated.
	# still want to update the cache though
	$S->cache->stamp('serial_'.$sid);
        $S->cache->store('serial_'.$sid, $chkser);
	return $chkser;

	}

sub make_serial {
	my $S = shift;
	my $sid = shift;
	$sid = shift if $sid eq 'story_new';

	my ($rv, $sth) = $S->db_insert({
	        INTO => 'story_trigger',
                COLS => 'sid, updated',
                VALUES => "'$sid', NOW()"
                });
        $sth->finish;
	return;
	}

sub major_serial_update {
	my $S = shift; # get rid of hook name
	shift;
	my $sid = shift;

	my $newser = $S->update_serial($sid);
	return $newser;
	}

sub minor_serial_update {
	my $S = shift;
	shift; # get rid of hook name
	my $sid = shift;

	my $newser = $S->update_serial($sid, 1);
	return $newser;
	}

sub story_view_serialchk {
	my $S = shift;
	shift; my $sid = shift;
	my $ser = $S->check_serial($sid);
	return $ser;
	}

1;
