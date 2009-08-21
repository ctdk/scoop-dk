package Scoop;
use strict;

sub edit_special {
	my $S = shift;
	my $msg = $S->_write_special_page();
	my $form = $S->_get_special_form($msg);
	return $form;
}


sub _get_special_form {
	my $S = shift;
	my $msg = shift || '&nbsp;';
	my $id = $S->{CGI}->param('id');
	my $pageid = $S->{CGI}->param('pageid');
	my $get = $S->{CGI}->param('get');
	my $delete = $S->{CGI}->param('delete');
	my $check_html = $S->{CGI}->param('html_check') || 0;
	my $spell_check = $S->{CGI}->param('spell_check') || 0;
	my $auto_format = $S->cgi->param('auto_format') || 0;

	if ($id eq '' && !$get) {
		$id = $pageid;
	}
	my ($page_selector, $page_data) = $S->_special_page_selector($id);

	$page_data->{content} = $page_data->{auth_content} if $page_data->{auth_content};
	$page_data->{content} =~ s/%%/\|/g;
	$page_data->{title} =~ s/"/&quot;/g;

	# Preserve &'s literally.
	$page_data->{content} =~ s/&/&amp;/g;

	# this is so that any tags in the special page don't trail out of the <textblock>
	$page_data->{content} =~ s/\</&lt;/g;
	$page_data->{content} =~ s/\>/&gt;/g;
	my $preview;

	if ($id && !$delete) {
		$preview = qq|
			<tr>
				<td>%%norm_font%%View <a href="%%rootdir%%/special/$id" target="new">$page_data->{title}</a> (opens in new window)%%norm_font_end%%</td>
			</tr>|;
	}
	my $chkhtml_checked = $check_html ? ' checked="checked"' : '';
	my $splchk_checked  = $spell_check ? ' checked="checked"' : '';
	my $af_checked = $auto_format ? ' checked="checked"' : '';
	my $upload_page = $S->display_upload_form(0,'content');
	$upload_page = "<tr><td>$upload_page</td></tr>" unless $upload_page eq '';

	my $page = qq|
		<form name="special" action="%%rootdir%%/" method="post" enctype="multipart/form-data">
		<input type="hidden" name="op" value="admin" />
		<input type="hidden" name="tool" value="special" />
		<table width="100%" border="0" cellpadding="0" cellspacing="0">
			<tr bgcolor="%%title_bgcolor%%">
				<td>%%title_font%%Edit Special Pages%%title_font_end%%</td>
			</tr>
			<tr><td>%%title_font%%<font color="#FF0000">$msg</font>%%title_font_end%%</td>			
			$preview
			<tr>
				<td>%%norm_font%%<b>Page:</b> $page_selector <input type="submit" name="get" value="Get Page" />%%norm_font_end%%</td>
			</tr>|;
	if ($id && !$delete) {
		$page .= qq|
			<tr>
				<td>%%norm_font%%<input type="checkbox" name="delete" value="1" /> Delete this page%%norm_font_end%%</td>
			</tr>|;
	}
	$page .= qq|
			<tr>
				<td>%%norm_font%%<b>Page ID:</b> <input type="text" name="pageid" value="$page_data->{pageid}" size="40" />%%norm_font_end%%</td>
			</tr>
			<tr>
				<td>%%norm_font%%<b>Title:</b> <input type="text" name="title" value="$page_data->{title}" size="40" />%%norm_font_end%%</td>
			</tr>	
			<tr>
				<td><input type="checkbox" name="html_check" value="1"$chkhtml_checked /> %%norm_font%%Check the HTML of this page%%norm_font_end%%</td>
			</tr>
			<tr>
				<td><input type="checkbox" name="auto_format" value="1"$af_checked /> %%norm_font%%Disable autoformatting this page.%%norm_font_end%%</td>
			</tr>
			|;
	if ($S->spellcheck_enabled()) {
			$page .= qq|
			<tr>
				<td><input type="checkbox" name="spell_check" value="1"$splchk_checked /> %%norm_font%%Spellcheck this page%%norm_font_end%%</td>
			</tr>|;
	}
	$page .= qq|
			<tr>
				<td>%%norm_font%%<b>Description:</b></td>
			</tr>
			<tr>
				<td>%%norm_font%%<textarea cols="50" rows="3" name="description" wrap="soft">$page_data->{description}</textarea>%%norm_font_end%%</td>
			</tr>
			<tr>
				<td>%%norm_font%%<b>Content:</b></td>
			</tr>
			<tr>
				<td>%%norm_font%%<textarea cols="50" rows="25" name="content" wrap="soft">$page_data->{content}</textarea>%%norm_font_end%%</td>
			</tr>
			$upload_page
			<tr>
			<td>%%norm_font%%<input type="submit" name="write" value="Save Page"> <input type="reset" />%%norm_font_end%%</td>
			</tr>
			</table>
			</form>|;

	return $page;
}

sub _special_page_selector {
	my $S = shift;
	my $id = shift;
	
	my ($rv, $sth) = $S->db_select({
		FORCE_MASTER => 1,
		WHAT => '*',
		FROM => 'special'});
	
	my $select = '';
	$select = ' selected="selected"' unless $id;
	my $page = qq|
		<select name="id" size="1">
		<option value=""$select>Select Special Page</option>|;
	
	my $return_data;	
	while (my $page_data = $sth->fetchrow_hashref) {
		$select = '';
		$page_data->{title} =~ s/"/&quot;/g;
		if ($id eq $page_data->{pageid}) {
			$select = ' selected="selected"';
			$return_data = $page_data;
		}
		$page .= qq|
			<option value="$page_data->{pageid}"$select>$page_data->{title}</option>|;
	}
	$sth->finish;
	$page .= qq|
		</select>|;
	
	return ($page, $return_data);
}

sub _write_special_page {
	my $S = shift;
	my $write = $S->{CGI}->param('write');

	return unless $write;

	my $id = $S->{CGI}->param('id');
	my $pageid = $S->{CGI}->param('pageid');
	my $title = $S->{CGI}->param('title');
	my $description = $S->{CGI}->param('description');
	my $content = $S->{CGI}->param('content');
	my $auth_content = $content;
	my $check_html = $S->{CGI}->param('html_check');
	my $spell_check = $S->{CGI}->param('spell_check');
	my $auto_format = $S->cgi->param('auto_format');

	my $q_id = $S->{DBH}->quote($pageid);
	# get this out of the way first, since it doesn't depend on anything else
	if ($S->{CGI}->param('delete') && $id) {
		my ($rv, $sth) = $S->db_delete({
			FROM  => 'special',
			WHERE => "pageid = $q_id"
		});
		$sth->finish;
		$S->cache->remove("special_" . $pageid);
		return "Page \"$title\" deleted.";
	}

	my ($errs, $files_written);
	if ($S->{CGI}->param('file_upload')) {
		my $file_upload_type = $S->{CGI}->param('file_upload_type');
		my ($return, $file_name, $file_size, $file_link) = $S->get_file_upload($file_upload_type);

		if ($file_upload_type eq 'content') {
			#replace content with uploaded file
			$content= $return unless $file_size ==0;
		} else { 
			# $return should be empty if we are doing a file upload, if not they are an error message
			$errs = $return;
			$files_written = qq{Saved File: <a href="$file_link">$file_name</a>}
				unless $file_link eq '';
		}
	}

	my @mis_spell;
	if ($spell_check && $S->spellcheck_enabled()) {
		my $callback = sub {
			my $word = shift;
			push(@mis_spell, $word);
			return $word;
		};

		if ($check_html) {
			$S->spellcheck_html_delayed($callback);
		} else {
			$S->spellcheck_html($content, $callback);
		}
	}

	if ($check_html) {
		my $page_ref = $S->html_checker->clean_html(\$content, '', 1);
		$content = $$page_ref;

		$errs .= $S->html_checker->errors_as_string
	}

	unless ($auto_format){
		$content = $S->auto_format($content);
		}

	if (@mis_spell) {
		my $words_are = (@mis_spell == 1) ? 'word is' : 'words are';
		my $sc_errs = "The following $words_are mis-spelled:<br />\n<ul>\n";
		foreach my $m (@mis_spell) {
			$sc_errs .= "<li>$m<br />\n";
		}
		$sc_errs .= "</ul>\n";

		$errs .= "<p>" if $errs;
		$errs .= $sc_errs;
	}

	return $errs if $errs;

	my $write_cont = $content;
	$write_cont =~ s/\|/%%/g;
	$write_cont =~ s/\\%%/\|/g;
	$write_cont = $S->{DBH}->quote($write_cont);
	my $q_title = $S->{DBH}->quote($title);
	my $q_desc  = $S->{DBH}->quote($description);
	$auth_content =~ s/\|/%%/g;
	$auth_content =~ s/\\%%/\|/g;
	$auth_content = $S->dbh->quote($auth_content);

	my ($rv, $sth);
	if ($id eq $pageid) {
		($rv, $sth) = $S->db_update({
			WHAT => 'special',
			SET => qq|title = $q_title, description = $q_desc, content = $write_cont, auth_content = $auth_content|,
			WHERE => qq|pageid = $q_id|});
	} else {
		($rv, $sth) = $S->db_insert({
			INTO => 'special',
			COLS => 'pageid, title, description, content, auth_content',
			VALUES => qq|$q_id, $q_title, $q_desc, $write_cont, $auth_content|});
	}
	$sth->finish;
	$S->cache->remove("special_" . $pageid);
	return "Page \"$title\" updated. $files_written" if $rv;
	my $err = $S->{DBH}->errstr;
	return "Error updating \"$title\". DB said: $err";
}

1;
