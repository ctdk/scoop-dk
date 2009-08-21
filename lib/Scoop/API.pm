package Scoop;

# handle all the api requests here, calling more specialized funcitons as
# necessary.

use constant API_VERSION => 0.017;

# err codes

use constant API_BAD_METHOD 		=> 2;
use constant API_BAD_ARGS		=> 3;
use constant API_BAD_AUTH		=> 4;

# further down error codes
use constant API_BAD_SECTION		=> 26;

sub api_handler {
	my $S = shift;
	my $method = $S->cgi->param('method');

	# set content type to be safe
	$S->apache->content_type('text/xml');

	# do authentication stuff as needed
	
	# execute methods.
	if ($method eq 'scoop.test.echo'){
		return $S->api_test_echo();
		}
	elsif ($method eq 'scoop.api_version'){
		return $S->api_version();
		}
	elsif ($method eq 'scoop.stories.current'){
		return $S->api_stories_list();
		}
	elsif ($method eq 'scoop.stories.list'){
		# Generic method for maximum flexibility
		return $S->api_stories_list($S->cgi->param('type'));
		}
	

	# last ditch default
	# XMLize later
	else {
		return $S->api_error();
		}

	}

# this test function just spits out whatever we send to it.

sub api_test_echo {
	my $S = shift;

	my $out;
	my $x = XML::Writer->new(OUTPUT => \$out, DATA_MODE => 1, DATA_INDENT => 1, ENCODING => 'utf-8');
	$x->xmlDecl("UTF-8");
	$x->startTag('rsp', 'stat' => 'ok');
	my @pnames = $S->{APR}->param;

	# FIXME: check out and see if we need to have an extra step to get the
	# POST parameters for this.

	foreach my $k (@pnames){
		$x->startTag($k);
		$x->characters($S->{PARAMS}->{$k});
		$x->endTag($k);
		}
	$x->endTag('rsp');
	$x->end;
	return $out;

	}

sub api_error {
	my $S = shift;

	my $err = shift || API_BAD_METHOD;
	my $errmsg = shift || "Unsupported API method.";

	my $out;
        my $x = XML::Writer->new(OUTPUT => \$out, DATA_MODE => 1, DATA_INDENT => 1, ENCODING => 'utf-8');
        $x->xmlDecl("UTF-8");
        $x->startTag('rsp', 'stat' => 'fail');
	$x->emptyTag('err', 'code' => $err, 'msg' => $errmsg);
	$x->endTag('rsp');
	$x->end;
	return $out;
	}

sub api_version {
	my $S = shift;
	my $out;
	my $x = XML::Writer->new(OUTPUT => \$out, DATA_MODE => 1, DATA_INDENT => 1, ENCODING => 'utf-8');
        $x->xmlDecl("UTF-8");
	$x->startTag('rsp', 'stat' => 'ok');
	$x->startTag('version');
	$x->characters(API_VERSION);
	$x->endTag('version');
	$x->endTag('rsp');
	$x->end;
	return $out;
	}

sub api_stories_list {
	my $S = shift;
	my $type = shift || "main";
	my $out;

	my $params = {};

	my $ds;
	if($type eq 'main'){
		$params->{displaystatus} = 0;
		}
	elsif($type eq 'section'){
		$params->{displaystatus} = [0,1];
		$params->{section} = $S->cgi->param('section');
		}
	elsif($type eq 'tag'){
		$params->{displaystatus} = [0,1];
		$params->{tag} = $S->cgi->param('tag');
		}
	elsif($type eq 'user'){
		$params->{displaystatus} = [0,1];
		$params->{user} = $S->cgi->param('user');
		}
	$params->{page} = $S->cgi->param('more') || 1;
	
	# make sure we're not trying to get a Forbidden Section
	if( $params->{section} && $params->{section} ne '' && $params->{section} ne '__all__' && !$S->have_section_perm( 'norm_read_stories', $params->{section} ) ) {
		return $S->api_error(API_BAD_SECTION, "Bad section requested");
		}

	my $sids = $S->get_story_ids($params);
	my $stories = $S->story_data_arr($sids);

	# TODO: support sending RSS 2.0 as well

	# spit out our XML
	my $x = XML::Writer->new(OUTPUT => \$out, DATA_MODE => 1, DATA_INDENT => 1, ENCODING => 'utf-8');
	$x->xmlDecl("UTF-8");
	$x->comment("RSS 2.0 support, at least, for story lists is planned for the future.");

	$x->startTag('rsp', 'stat' => 'ok');

	foreach my $story (@{$stories}){
		$x->startTag('story');
		$x->startTag('url');
		$x->characters($S->{UI}->{VARS}->{site_url} . $S->{UI}->{VARS}->{rootdir} . "/storyonly/$story->[0]/" . $S->moduloze($story->[26]) . "/$story->[26]");
		$x->endTag('url');
		$x->emptyTag('id', 'value' => $story->[26]);
		$x->startTag('title');
		$x->characters($story->[3]);
		$x->endTag('title');
		$x->emptyTag('author', 'nick' => $story->[30], 'uid' => $story->[2]);
		$x->startTag('pubDate');
		$x->characters($story->[33]);
		$x->endTag('pubDate');
		$x->startTag('intro');
		$x->characters($story->[6]);
		$x->endTag('intro');
		$x->startTag('storyTags');
		my $tags = $S->get_tags($story->[0]);
		foreach (@{$tags}){
			$x->startTag('tag');
			$x->characters($_);
			$x->endTag('tag');
			}
		$x->endTag('storyTags');
		$x->endTag('story');
		}

	$x->endTag('rsp');
	$x->end;
	return $out;
	}

1;
