package Scoop;
use strict;
my $DEBUG = 0;

sub comment_prefs {
	my $S = shift;
	my $err;
	
	$S->{UI}->{BLOCKS}->{subtitle} = 'Comment Preferences';

	if ($S->cgi->param('save') eq 'Save') {
		$err = $S->_save_comment_prefs();
	}
	
	my $form = $S->comment_prefs_form();
	
	$S->{UI}->{BLOCKS}->{CONTENT} = qq|
		<TABLE CELLPADDING=0 CELLSPACING=0 BORDER=0 width="100%">
		<TR>
			<TD BGCOLOR="%%title_bgcolor%%">
			%%title_font%%<B>Edit Comment Preferences for $S->{NICK}</B>%%title_font_end%%
			</TD>
		</TR>
		<TR>
			<TD ALIGN="center">%%title_font%%
			<P><FONT COLOR="#FF0000">$err</FONT><P>%%title_font%%
			</TD>
		</TR>
		<TR>
			<TD>
			$form
			</TD>
		</TR>
		</TABLE>|;
	
	return;	
}
	
sub comment_prefs_form {
	my $S = shift;
	
	my ($flat_to, $flat_unthread_to, $nested_to, $threaded_to, $dthreaded_to, $dminimal_to, $minimal_to) = $S->comment_prefs_form_values();

	#$S->_set_comment_order();
	#$S->_set_comment_rating_thresh();
	#$S->_set_comment_type();
	#$S->_set_comment_rating_choice();
	$S->set_comment_posttype();
	$S->set_comment_sig_behavior();
	
	my $comment_order_select = $S->_comment_order_select();
	my $comment_rating_select = $S->_comment_rating_select();
	my $rating_choice = $S->_comment_rating_choice();
	my $hidden_choice = $S->_comment_hiding_choice();
	my $comment_type_select = $S->_comment_type_select();
	my $sig_opt = $S->_sig_option_form($S->user_data($S->{UID}));
	my $post_opt = $S->_postmode_option_form();


	my $form = qq|
			<FORM NAME="commentprefs" METHOD="POST" ACTION="%%rootdir%%/">
			<INPUT TYPE="hidden" NAME="op" VALUE="interface">
			<INPUT TYPE="hidden" NAME="tool" VALUE="comments">
			<TABLE BORDER=0 CELLPADDING=3 CELLSPACING=0>
				<TR>
					<TD colspan=2>%%norm_font%%
					<B>Display Options:</B><P>
					For each of the following display modes, 
					enter the maximum number of comments to display in that mode. The closest 
					matching mode will be used for any given comment page. 
					Example: If you set "Nested" up to 100 and 
					"Threaded" up to 200, a page with 40 comments will use nested mode, and a page 
					with 120 comments will use threaded mode. The "count" is the number of comments 
					that will be shown on each specific comment page, which means that the display 
					mode will adapt to the number of comment being shown right now, which is nice. :-)
					<P>
					Leaving a box blank will cause a mode to never be used. Enter a <B>+</B> 
					to make a mode be used for any number of comments above the highest 
					listed number. <B>You must mark exactly one mode with a "+".</B>
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD>%%norm_font%%<B>
					Flat (threaded) up to:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					<INPUT TYPE="text" SIZE=5 NAME="flat_to" VALUE="$flat_to">
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD>%%norm_font%%<B>
					Flat (unthreaded) up to:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					<INPUT TYPE="text" SIZE=5 NAME="flat_unthread_to" VALUE="$flat_unthread_to">
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD>%%norm_font%%<B> 
					Nested up to:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					<INPUT TYPE="text" SIZE=5 NAME="nested_to" VALUE="$nested_to">
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD>%%norm_font%%<B> 
					Threaded up to:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					<INPUT TYPE="text" SIZE=5 NAME="threaded_to" VALUE="$threaded_to">
					%%norm_font_end%%</TD>
				</TR>|;
	if($S->{UI}->{VARS}->{allow_dynamic_comment_mode}) {
		$form .= qq|
				<TR>
					<TD>%%norm_font%%<B> 
					Dynamic Threaded up to:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					<INPUT TYPE="text" SIZE=5 NAME="dthreaded_to" VALUE="$dthreaded_to">
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD>%%norm_font%%<B> 
					Dynamic Minimal up to:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					<INPUT TYPE="text" SIZE=5 NAME="dminimal_to" VALUE="$dminimal_to">
					%%norm_font_end%%</TD>
				</TR>|;
	}
	$form .= qq|
				<TR>
					<TD>%%norm_font%%<B> 
					Minimal up to:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					<INPUT TYPE="text" SIZE=5 NAME="minimal_to" VALUE="$minimal_to">
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD colspan=2>%%norm_font%%
					The following are comment type and order options.
					%%norm_font_end%%</TD>
				</TR>|;
	if ($comment_type_select) {
		$form .= qq|
				<TR>
					<TD>%%norm_font%%<B> 
					View:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					$comment_type_select
					%%norm_font_end%%</TD>
				</TR>|;
	}
	
	my $hide_hidden;
	if ($S->{UI}->{VARS}->{use_mojo} && $S->{TRUSTLEV} == 2 || $S->have_perm('super_mojo')) {
		$hide_hidden = qq|
				<TR>
					<TD>%%norm_font%%<B> 
					Show hidden comments?
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					$hidden_choice
					%%norm_font_end%%</TD>
				</TR>
		|;
	}
		
	$form .= qq|
				<TR>
					<TD>%%norm_font%%<B> 
					Sort:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					$comment_rating_select $comment_order_select
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD>%%norm_font%%<B> 
					Rate comments?
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					$rating_choice
					%%norm_font_end%%</TD>
				</TR>
				</TR>
				$hide_hidden
				<TR>
					<TD colspan=2>%%norm_font%%
					<P>
					<hr width="100%" SIZE=0 NOSHADE>
					<P>
					<B>Posting options:</B>
					%%norm_font_end%%</TD>
				</TR>
				<TR>
					<TD>%%norm_font%%<B> 
					Post mode:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					$post_opt
					%%norm_font_end%%</TD>
				</TR>|;

	if ($S->{UID} > 0 && $S->{UI}->{VARS}->{allow_sig_behavior} ) {					
		$form .= qq|
				<TR>
					<TD>%%norm_font%%<B> 
					Signature type:
					</B>%%norm_font_end%%</TD>
					<TD>%%norm_font%% 
					$sig_opt
					%%norm_font_end%%</TD>
				</TR>|;
	}
	
	$form .= qq|		
			</TABLE>
			<INPUT TYPE="submit" NAME="save" VALUE="Save">
			</FORM>|;
	
	return $form;
}

sub comment_prefs_form_values {
	my $S = shift;
	my $in_only = shift;
	
	my $flat_to = $S->cgi->param('flat_to');
	my $flat_unthread_to = $S->cgi->param('flat_unthread_to');
	my $nested_to = $S->cgi->param('nested_to');
	my $threaded_to = $S->cgi->param('threaded_to');
	my $minimal_to = $S->cgi->param('minimal_to');
	my $dthreaded_to = $S->cgi->param('dthreaded_to');
	my $dminimal_to = $S->cgi->param('dminimal_to');

	unless ($in_only) {
		$flat_to ||= $S->{prefs}->{comment_flat_to};
		$flat_unthread_to ||= $S->{prefs}->{comment_flat_unthread_to};
		$nested_to ||= $S->{prefs}->{comment_nested_to};
		$threaded_to ||= $S->{prefs}->{comment_threaded_to};
		$dthreaded_to ||= $S->{prefs}->{comment_dthreaded_to};
		$dminimal_to ||= $S->{prefs}->{comment_dminimal_to};
		$minimal_to ||= $S->{prefs}->{comment_minimal_to};
	}
	
	return ($flat_to, $flat_unthread_to, $nested_to, $threaded_to, $dthreaded_to, $dminimal_to, $minimal_to);
}


sub _save_comment_prefs {
	my $S = shift;
	
	my ($flat_to, $flat_unthread_to, $nested_to, $threaded_to, $dthreaded_to, $dminimal_to, $minimal_to) = $S->comment_prefs_form_values(1);
	my $type = $S->cgi->param('commenttype');
	my $rating = $S->cgi->param('commentrating');
	my $rating_choice = $S->cgi->param('ratingchoice');
	my $posttype = $S->cgi->param('posttype');
	my $sig_behavior = $S->cgi->param('sig_behavior');
	my $commentorder = $S->cgi->param('commentorder');
	my $hidingchoice = 	$S->cgi->param('hidingchoice');
	# Check inputs
	my $plus = 0;
	my %values;
	foreach my $v ($flat_to, $flat_unthread_to, $nested_to, $threaded_to, $dthreaded_to, $dminimal_to, $minimal_to) {
		next unless ($v);
		
		if ($v !~ /^\d+$/ && $v !~ /^\+$/) {
			return "Error! Please use only numbers or a + (by itself) for values.";
		}
		
		if ($v =~ /^\+$/ && $plus) {
			return "Error! You can only designate one mode with a +.";
		}
		
		if ($v =~ /^\+$/) {
			$plus = 1;
		}
		if ($values{$v}) {
			return "Error! You have marked more than one mode with the same value.";
		}
		$values{$v} = 1;
	}

	unless ($plus == 1) {
		return "Error! You must designate one mode as the \"fallback\" with a +.";
	}
	
	my $p_save = {
		'comment_flat_to'     => $flat_to,
		'comment_flat_unthread_to' => $flat_unthread_to,
		'comment_nested_to'   => $nested_to,
		'comment_minimal_to'  => $minimal_to,
		'comment_threaded_to' => $threaded_to,
		'comment_dthreaded_to' => $dthreaded_to,
		'comment_dminimal_to' => $dminimal_to,
		'comment_commenttype' => $type,
		'comment_commentrating' => $rating,
		'comment_ratingchoice' => $rating_choice,
		'comment_posttype'    => $posttype,
		'comment_sig_behavior' => $sig_behavior,
		'comment_commentorder' => $commentorder,
		'comment_hidingchoice' => $hidingchoice
	};
	
	# Clear old prefs
    my ($rv, $sth) = $S->db_delete({
    	FROM    =>      'userprefs',
    	WHERE   =>      qq|uid = $S->{UID} and prefname LIKE "comment_%"|,
    	DEBUG   =>      0});

    unless ($rv) {
	    return $S->{DBH}->errstr();
    }

	my $err;
	# Save new prefs
	foreach my $key (keys %{$p_save}) {
		next unless ($p_save->{$key});
		my ($rv, $sth) = $S->db_insert({
        	INTO    => 'userprefs',
        	COLS    => qq|uid, prefname, prefvalue|,
        	VALUES  => qq|$S->{UID}, "$key", "$p_save->{$key}"|,
        	DEBUG   =>      0});
        
		unless ($rv) {
        	$err .= $S->{DBH}->errstr();
        }
	}
	
	return $err if ($err);
	$S->_set_prefs(1);
	$S->_set_vars();
	$S->_set_blocks();
	$S->_update_pref_config();
	
	#$S->_set_comment_order();
	#$S->_set_comment_rating_thresh();
	#$S->_set_comment_type();
	#$S->_set_comment_rating_choice();
	$S->set_comment_posttype();
	$S->set_comment_sig_behavior();
	
	
	return "Comment prefs saved.";
}
			
1;
