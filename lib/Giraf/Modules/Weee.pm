#! /usr/bin/perl
$|=1;

package Giraf::Modules::Weee;

use strict;
use warnings;

use Giraf::Admin;

# Private vars
our @_ovations=(['\o/'], ['\o/'], ['\o/'], ['\o/'], ['\o/'], ['\o/'], ['\o/','\\\\o','o//'], ['<o/'],['\\o>'],['\o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/ \o/'] );

sub init {
	my ($kernel,$irc) = @_;
	Giraf::Module::register('public_parser','weee','bot_weee',\&bot_weee,'(\B[<>/|_\\\]o[/<>|_\\\]\B)|(\B[</|_\\\>]{2}o)|(o[/<>|_\\\]{2}\B)');
}

sub unload {
	Giraf::Module::unregister('public_parser','weee','bot_weee');
}

sub bot_weee {
	my($nick, $dest, $what)=@_;
	Giraf::Core::debug("bot_weee()");
	my @return;
	my $rand=int(rand(scalar(@_ovations)));
	my $ref=$_ovations[$rand];
	foreach my $e (@$ref)
	{
		my $ligne={ action =>"MSG",dest=>$dest,msg=>$e};
		push(@return,$ligne);
	}
	return @return;
}

1;

