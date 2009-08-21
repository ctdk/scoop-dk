package Scoop;
use strict;

sub submit_story_form {
	my $S = shift;
	my $message = "";    # prevent warnings
	my $preview = $S->{CGI}->param('preview');
	my $posttype = $S->{CGI}->param('posttype');
	my $params = $S->{CGI}->Vars_cloned;
	my $content;

	$S->set_comment_posttype();

	if ($params->{spellcheck} && $S->spellcheck_enabled()) {
		$S->spellcheck_html_delayed();
	}

	foreach my $e (qw(intro body)) {
		my $k = $e . 'text';
		$params->{$k} = $S->filter_comment($params->{$k}, $e, $posttype);
		my $errors = $S->html_checker->errors_as_string("in the $k");
		$message .= $errors if $errors;
	}
	$S->html_checker->clear_text_callbacks() if $params->{spellcheck};

	$params->{title} = $S->filter_subject($params->{title});
	$params->{dept} = $S->filter_subject($params->{dept});

	if ($params->{spellcheck} && $S->spellcheck_enabled()) {
		$params->{title} = $S->spellcheck_string($params->{title});
		$params->{dept} = $S->spellcheck_string($params->{dept});
	}

	# check the input, so they choose a topic, title, and have introtext
	my $topic   = $S->{CGI}->param('tid');
	my $title   = $S->{CGI}->param('title');
	my $intro   = $S->{CGI}->param('introtext');
	my $section = $S->{CGI}->param('section');

	if ($preview) {
		unless ($title && 
			    ((($topic) && ($topic ne 'all')) || !$S->{UI}->{VARS}->{use_topics}) && 
				$intro && 
				(($section) && ($section ne 'all'))) {
			$message = "Please fill in a value for the following fields: ";
			my @missing;

			unless( $title ) {
				push @missing, "title";
			}
			if ($S->{UI}->{VARS}->{use_topics}
			  && !($topic && $topic ne 'all')) {
				push @missing, "topic";
			}
			unless( $intro ) {
				push @missing, "intro";
			}
			unless( $section && $section ne 'all') {
				push @missing, "section";
			}

			$message .= join(', ', @missing);
			$preview = 1;
			$S->param->{preview} = 'preview';
		}
		# And give it a run through _check_story_validity as well
		my $tsid = 'preview';
		my ($rv, $errmsg) = $S->_check_story_validity($tsid, $params);
		if(!$rv){
		    $message .= $errmsg;
		    $S->param->{preview} = 'preview';
		    }
	}

	# check the length of the title. if it's too long, cut it down for the
	# preview (so they can see what the max length is), and give an error
	if (length($params->{title}) > 100) {
		$params->{title} = $S->cut_title($params->{title}, 100);
		$message .= "<br />\n" if $message;
		$message .= 'Title is too long (max length is 100 characters).';
	}

        if ($preview) {

                my $tmpsid = 'preview';
                $content .= $S->displaystory($tmpsid, $params);
                $content .= qq|
                        <TR>
                                <TD><FONT face="%%norm_font_face%%" size="%%norm_font_size%%" color="FF0000">$message</FONT></TD>
                        </TR><TR><TD>&nbsp;</TD></TR>|;
        }

	
	my $guidelines = $S->{UI}->{BLOCKS}->{submission_guidelines};
	
	if ($section ne '' && $section eq 'Diary') {
		$guidelines = $S->{UI}->{BLOCKS}->{diary_guidelines};
	}
	
	my $form = $S->edit_story_form('public');
	
	unless ($preview) {
		$form =~ s/%%guidelines%%/$guidelines/g;
	}
		
	return ($content, $form);
}

1;
