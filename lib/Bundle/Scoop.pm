package Bundle::Scoop;

# $Id: Scoop.pm,v 1.9 2005/01/27 19:37:16 janra Exp $

use strict;

$Bundle::Scoop::VERSION = '1.1';

1;

__END__

=head1 NAME

Bundle::Scoop - Bundle to install all the pre-requisites for Scoop

=head1 CONTENTS

Term::ReadKey
MD5
Digest::MD5 
MIME::Base64
Data::ShowTable
Storable
DBI
DBD::mysql
Apache::DBI
Apache::Request
Apache::SIG
Class::Singleton
Crypt::UnixCrypt
Crypt::CBC
Crypt::Blowfish
Mail::Sendmail
String::Random
Time::Timezone 
Time::CTime
Time::ParseDate
Image::Size
URI
HTML::Tagset
HTML::HeadParser
HTTP::Request
LWP::UserAgent
XML::Parser
XML::RSS
Date::Calc

=head1 DESCRIPTION

Install all the modules needed for Scoop. 

=head1 MORE INFORMATION

News, package repository and more information:

 http://scoop.kuro5hin.org/

=head1 AUTHOR

Rusty Foster <rusty@kuro5hin.org>, who shamelessly copied the work of Chris Winters <chris@cwinters.com>

=cut
