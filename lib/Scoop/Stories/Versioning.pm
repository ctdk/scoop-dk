package Scoop;
use strict;

#use Text::Diff;
#use Text::Diff::HTML;
use Compress::Zlib;

sub save_story_version {
	my $S = shift;
	my $sid = shift;
	my $title = shift;
	my $intro = shift;
	my $body = shift;

	# compressinate, but only intro and body
	my $cintro = compress($intro);
	my $cbody = compress($body);
	my $qsid = $S->dbh->quote($sid);
	my $qcintro = $S->dbh->quote($cintro);
	my $qcbody = $S->dbh->quote($cbody);
	my $qtitle = $S->dbh->quote($title);
	# get version
	my ($rv, $sth) = $S->db_select({
		WHAT => 'version, (unix_timestamp(now()) - unix_timestamp(time)) as diff',
		FROM => 'story_version',
		WHERE => "sid = $qsid",
		ORDER_BY => 'version DESC',
		GROUP_BY => 'version',
		LIMIT => 1
		});
	my $vers = $sth->fetchrow_hashref();
	$sth->finish;
	my $ver = $vers->{version};
	return if ($vers->{diff} < 2 && $rv != 0);
	$ver++;
	# insert
	($rv, $sth) = $S->db_insert({
		INTO => 'story_version',
		COLS => 'sid, version, aid, title, intro, body, time',
		VALUES => "$qsid, $ver, $S->{UID}, $qtitle, $qcintro, $qcbody, NOW()"
		});
	$sth->finish;
	# clean up old versions
	my $del = $ver - 20;
	if ($del > 0){
		($rv, $sth) = $S->db_delete({
			FROM => 'story_version',
			WHERE => "sid = $qsid AND version <= $del"
			});
		$sth->finish;
		}
	# guess that's it for that
	return;
	}

sub version_update_sid {
	my $S = shift;
	my $sid = shift;
	my $newsid = shift;
	# in case the sid has changed, we need to do it here too
	my $qsid = $S->dbh->quote($sid);
	my $qnewsid = $S->dbh->quote($newsid);
	my ($rv, $sth) = $S->db_update({
		WHAT => 'story_version',
		SET => "sid = $qnewsid",
		WHERE => "sid = $qsid"
		});
	$sth->finish;
	return;
	}

# show previous versions of a story
sub story_version {
	my $S = shift;
	my $sid = $S->cgi->param('sid');
	my $version = $S->cgi->param('version'); # in case we're examining
						 # only one version
	my $qsid = $S->dbh->quote($sid);
	my $sd = $S->story_basic_data_arr($sid);
	unless ($sd->[2] == $S->{UID} || $S->have_perm('story_admin')){
		return "<h2><b>Permission Denied</b></h2>";
		}
	my $content;
	if($version){
		my $date_format = $S->date_format('time');
		my ($rv, $sth) = $S->db_select({
                        WHAT => "sid, version, aid, title, intro, body, $date_format as ftime",
                        FROM => 'story_version',
                        WHERE => "sid = $qsid AND version = $version"
                        });		
		my $v = $sth->fetchrow_hashref();
		my $nick = $S->get_nick_from_uid($v->{aid});
		my $intro = uncompress($v->{intro});
		my $body = uncompress($v->{body});
		$content = qq|<h2>$v->{title}</h2><p><i>by <a href="/users/$nick">$nick</a> on $v->{ftime}<br /><textarea cols="50" rows="20">$intro</textarea></p><p><textarea cols="50" rows="20">$body</textarea></p>|;
		}
	else {
		my $date_format = $S->date_format('time');
		my ($rv, $sth) = $S->db_select({
			WHAT => "sid, version, aid, title, intro, body, $date_format as ftime",
			FROM => 'story_version',
			WHERE => "sid = $qsid",
			ORDER_BY => 'version desc'
			});
		if($rv == 0){
			return "<i>Sorry, no previous versions of this story have been saved.</i>";
			}
		while (my $v = $sth->fetchrow_hashref()){
			my $nick = $S->get_nick_from_uid($v->{aid});
			$content .= qq|$v->{version}: <a href="/storyversion/$v->{sid}?version=$v->{version}">$v->{title}</a> by <a href="/users/$nick">$nick</a> on $v->{ftime}<br />|;
			}
		}
	return $content;
	}





1;
