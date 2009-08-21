package Scoop;
use strict;

sub ajax_story_editor {
	my $S = shift;
	# the bare beginnings, I guess
	return '' if !$S->have_perm('story_post');
	my $section = $S->cgi->param('section');

	# first, we generate a sid
	my $sid = $S->create_story_stub($section);
	if($sid) {
		my $url = $S->{UI}->{VARS}->{site_url} . "/" .
          		$S->{UI}->{VARS}->{rootdir} .
          		"story/$sid?new=true";
		$S->{APACHE}->headers_out->{'Location'} = $url;
		$S->{HEADERS_ONLY}=1;
		}
	else { 
		my $err = "There was a problem creating a story.";
		return $err;
		}

	return;
	}

sub create_story_stub {
	my $S = shift;
	my $section = shift;
	my ($scol, $sval);
	unless ($S->have_section_perm('autosec_post_stories', $section)){
		return 0;
		}
	if(!$section && !$S->have_perm('story_admin')){
		return 0;
		}
	elsif(!$section){
		$section = 'Misc';
		}
	$section = $S->dbh->quote($section) if $section;
	if($section){
		$scol = ', section';
		$sval = ", $section";
		}
	
	my $sid = $S->make_new_sid();
	my $edisp = -4;
	my $qid = $S->_generate_unique_qid();
	my $nqid = $S->dbh->quote($qid);
	my $isq = ($S->cgi->param('isQuick')) ? 1 : 0;
	
	my $utitle = ($S->cgi->param('section') eq 'Diary') ? 'untitled diary' : 'untitled story';
	my ($rv, $sth) = $S->db_select({
	                WHAT => 'sid',
	                FROM => 'stories',
	                WHERE => "aid = $S->{UID} AND author_intro IS NULL AND author_body IS NULL AND author_title = '$utitle' AND displaystatus = -4 AND time < DATE_SUB(NOW(), INTERVAL 24 HOUR)",
			LIMIT => 1
	                });
        #my $exsid = $sth->fetchrow;
	my $exsid = 0;
        $sth->finish;
        #return $exsid if $exsid;
	if($exsid){
		$S->db_update({
			WHAT => 'stories',
			SET => 'time = NOW()',
			WHERE => "sid = '$exsid'"
			});
		return $exsid;
		}
	($rv, $sth) = $S->db_insert({
		DEBUG => 0,
		INTO => 'stories',
		COLS => "sid, dsid, title, author_title, aid, displaystatus, attached_poll, goatse_draft, is_quick, time$scol",
		VALUES => qq|'$sid', '$sid', '$utitle', '$utitle', $S->{UID}, $edisp, $nqid, 1, $isq, NOW()$sval|
		});
	$sth->finish;
	# and make a new poll stub too
        my ($rv2, $sth2) = $S->db_insert({
		INTO => 'pollquestions',
		COLS => 'qid, unpublished, voters',
		VALUES => "$nqid, 1, 0"
		});
	$S->run_hook('story_new',$sid, $utitle, '', '', '');
	my $uid = $S->{UID};
	$S->cache->remove("drafts_$uid");
	return ($rv) ? $sid : 0;
	}

sub story_poll_aid {
        my $S = shift;
        my $sid = shift;

        if(my $raid = $S->cache->fetch("spa_$sid")){
                return $raid;
                }
        my $q_sid = $S->dbh->quote($sid);
        # if we don't have it, fetch it and cache it.
	my ($rv, $sth) = $S->db_select({
		ARCHIVE => $S->_check_archivestatus($sid),
                WHAT => 'aid',
	        FROM => 'stories',
                WHERE => "sid = $q_sid"
                });
	my $aid = $sth->fetchrow();
        $sth->finish;
        $S->cache->store("spa_$sid", $aid);
        return $aid;
        }

sub story_basic_data {
        my $S = shift;
        my $sid = shift;
	# at least now we'll be able to use *some* form of the story_cache,
        # even though we won't be able to use it for everything.
        # Non-personalized data
	if(my $ret = $S->story_cache->get($sid)){
                return $ret;
                }
        # get the info

	# ideally, we'd be able to adjust the time depending on the timezone
        # of the requesting user, so we won't have to be reloading the cache
	# everytime a change is made for multiple timezones
	# first, though, just get it working with having to have the stuff
	# for multiple timezones. The story_cache stuff will at least keep
	# that separate.

        my $date_format = $S->date_format('time');
        my $q_sid = $S->dbh->quote($sid);
        my ($rv, $sth) = $S->db_select({
                ARCHIVE => $S->_check_archivestatus($sid),
                WHAT => "*, $date_format as ftime",
                FROM => 'stories',
                WHERE => "sid = $q_sid"
                });
        my $story = $sth->fetchrow_hashref();
	$sth->finish;
        # store this bitch.
        $S->story_cache->set($sid, $story);
        # and send it back
        return $story;
        }

# Wow, looks like updating the sid actually causes a *lot* of problems. Eep.
# I guess now we'll finally get to use the transaction support to delete the
# story, comments, and tags, reinsert them with the right data

sub update_sid {
        my $S = shift;
        my $sid = shift;
        my $newsid = shift;

        # Ooof, we've got a lot of stuff to do.
        my ($rv, $sth);
        # As weird sounding as this is, we should probably start the
        # transaction first. That way, if the SELECT statement even fail for
        # some reason, we don't fuck everything up. Ooof.
        # Create the temp tables first, though. Otherwise, it looks like the
        # transaction will implicitly commit, and we really, really don't
        # want that.
        my $storytmp = $S->create_temp_table("stories");
        my $commentstmp = $S->create_temp_table("comments");
        my $tagstmp = $S->create_temp_table("story_tags");
        unless ($S->db_start_transaction()){
                warn "Transaction failed to start!\n";
                return (0, "Transaction failed to start\n!");
                }

        # Now, we stick all our work in a giant eval {}
        eval {          # BEGIN TRANSACTION EVAL
                # stories first.
                # insert into temp table
                $S->db_insert({
                        INTO => $storytmp,
                        SELECT => "SELECT * FROM stories WHERE sid = '$sid'"
                        });
                # rename sid in temp table
                $S->db_update({
                        WHAT => $storytmp,
                        SET => "sid = '$newsid'",
                        WHERE => "sid = '$sid'"
                        });
                # delete the old one
                $S->db_delete({
                        FROM => 'stories',
                        WHERE => "sid = '$sid'"
                        });
                # and finally insert the new one
                $S->db_insert({
                        INTO => 'stories',
                        SELECT => "SELECT * FROM $storytmp WHERE sid = '$newsid'
"
                        });
                # now we just repeat the process for comments and tags
                $S->db_insert({
                        INTO => $commentstmp,
                        SELECT => "SELECT * FROM comments WHERE sid = '$sid'"
                        });
                $S->db_update({
                        WHAT => $commentstmp,
                        SET => "sid = '$newsid'",
                        WHERE => "sid = '$sid'"
                        });
                $S->db_delete({
                        FROM => 'comments',
                        WHERE => "sid = '$sid'"
                        });
                $S->db_insert({
                        INTO => 'comments',
                        SELECT => "SELECT * FROM $commentstmp WHERE sid = '$newsid'"
                        });
                $S->db_insert({
                        INTO => $tagstmp,
                        SELECT => "SELECT * FROM story_tags WHERE sid = '$sid'"
                        });
                $S->db_update({
                        WHAT => $tagstmp,
                        SET => "sid = '$newsid'",
                        WHERE => "sid = '$sid'"
                        });
                $S->db_delete({
                        FROM => 'story_tags',
                        WHERE => "sid = '$sid'"
                        });
                $S->db_insert({
                        INTO => 'story_tags',
                        SELECT => "SELECT * from $tagstmp WHERE sid = '$newsid'"
                        });
                # should probably clear out the tag versions too -- they won't
                # be doing anything, but they aren't that necessary at this
                # stage
                $S->db_delete({
                        FROM => 'story_tags_ver',
                        WHERE => "sid = '$sid'"
                        });
                };      # END TRANSACTION EVAL
        # let's check if it worked.
        ($rv, $sth) = $S->db_select({
		FORCE_MASTER => 1,
                WHAT => 'count(*)',
                FROM => 'stories',
                WHERE => "sid = '$newsid'"
                });
        my $cnt = $sth->fetchrow();
        if($@ || !$cnt){
                # crap, it didn't work
                $S->db_rollback();
                return (0, "Transaction failed, rolling back. Error message was:
 $@\n");
                }
        else {
                # commit and figure out what we want to sent back
                $S->db_commit();
                # Cleanup, cleanup, all the mod_perls everywhere
                delete $S->{STORY_CACHE}->{$sid};
		$S->story_cache->del($sid);
                $S->story_cache->asd_del($sid);
                $S->story_cache->del_arr($sid);
                $S->story_cache->asd_del_arr($sid);
		my $kid = $S->get_story_id_from_sid($newsid);
		delete $S->{ID_CACHE}->{$kid};
		$S->cache->remove("s_sid_f_id_$kid");
		$S->cache->remove("kurl_$kid");
		my $ksid = $S->get_sid_from_story_id($kid);
                # if I ever find where the comment stuff is being cached, get
                # that too
                $S->clear_tags($sid);
		# update the sid for the previous versions too
		$S->version_update_sid($sid, $newsid);
                return ($newsid, "Sid successfully updated, story saved.");
                }
        }

1;
