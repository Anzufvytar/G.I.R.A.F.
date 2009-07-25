#! /usr/bin/perl
$| = 1;

package Giraf::Admin;

use strict;
use warnings;

use Giraf::Config;
use Giraf::Module;
use Giraf::Chan;
use Giraf::User;
use Giraf::Trigger;

use DBI;
use Switch;

# Public vars

# Private vars
our $_kernel;
our $_irc;
our $_dbh;
our $_botname;

our $_tbl_config='config';
our $_tbl_modules_access='modules_access';
our $_tbl_chan_admin='chan_admin';
our $_tbl_users_in_chan='users_in_chan';
our $_tbl_users;
our $_tbl_chans;
our $_tbl_modules;

our $_auth_modules;

sub init {
	my ( $ker, $irc_session, $botname) = @_;
	$_kernel  = $ker;
	$_irc     = $irc_session;
	$_botname = $botname;

	Giraf::Core::debug("Giraf::Admin::init()");

	$_tbl_users=$Giraf::User::_tbl_users;
	$_tbl_chans=$Giraf::Chan::_tbl_chans;
	$_tbl_modules=$Giraf::Module::_tbl_modules;

	$_dbh=get_dbh();
	$_dbh->do("BEGIN TRANSACTION");
	$_dbh->do("CREATE TABLE IF NOT EXISTS $_tbl_config (name TEXT PRIMARY KEY, value TEXT);");
	$_dbh->do("CREATE TABLE IF NOT EXISTS $_tbl_modules_access (module_name TEXT REFERENCES $_tbl_modules (name), chan_name TEXT REFERENCES $_tbl_chans (name), disabled NUMERIC DEFAULT 0, UNIQUE (module_name,chan_name) );");
	$_dbh->do("CREATE TABLE IF NOT EXISTS $_tbl_chan_admin (chan_name TEXT REFERENCES $_tbl_chans (name), user_UUID TEXT REFERENCES $_tbl_users (UUID))");
	$_dbh->do("CREATE TABLE IF NOT EXISTS $_tbl_users_in_chan (chan_name TEXT REFERENCES $_tbl_chans (name), user_UUID TEXT REFERENCES $_tbl_users (UUID))");
	$_dbh->do("DELETE FROM $_tbl_users_in_chan");
	$_dbh->do("COMMIT");

	Giraf::Trigger::register('public_function','core','bot_admin_main',\&bot_admin_main,'admin');
	Giraf::Trigger::register('public_function','core','bot_register',\&bot_register,'register');
	Giraf::Admin::module_authorized_update();
}

#Utility subs
sub set_param {
	my ($param,$value)=@_;

	Giraf::Core::debug("Giraf::Admin::set_param($param,$value)");

	my $sth=$_dbh->prepare("INSERT OR REPLACE INTO $_tbl_config(name,value) VALUES(?,?)");
	$sth->execute($param,$value);
	return $param;
}

sub get_param {
	my ($name) = @_;
	
	Giraf::Core::debug("Giraf::Admin::get_param($name)");
	
	my $value;
	my $sth=$_dbh->prepare("SELECT value FROM $_tbl_config WHERE name LIKE ?");
	$sth->bind_columns(\$value);
	$sth->execute($name);
	$sth->fetch();
	return $value;
}

sub get_dbh {

	Giraf::Core::debug("Giraf::Admin::get_dbh()");

	if( !$_dbh )
	{
		$_dbh=DBI->connect(Giraf::Config::get('dbsrc'), Giraf::Config::get('dbuser'), Giraf::Config::get('dbpass'));
	}
	return $_dbh;
}

#Admin subs
sub bot_admin_main {
	my ($nick,$dest,$what)=@_;

	Giraf::Core::debug("Giraf::Admin::bot_admin_main()");

	my @return;
	my ($sub_func,$args,@tmp);
	@tmp=split(/\s+/,$what);
	$sub_func=shift(@tmp);
	$args="@tmp";

	Giraf::Core::debug("admin main : sub_func=$sub_func");

	switch ($sub_func)
	{
		case 'module'		{	push(@return,bot_admin_module($nick,$dest,$args)); }
		case 'user'		{	push(@return,bot_admin_user($nick,$dest,$args)); }
		case 'join'		{	push(@return,bot_join($nick,$dest,$args)); }
		case 'part'		{	push(@return,bot_part($nick,$dest,$args)); }
	}

	return @return;
}

sub bot_admin_module {
	my ($nick,$dest,$what)=@_;

	Giraf::Core::debug("Giraf::Admin::bot_admin_module($what)");

	my @return;
	my ($sub_func,$args,@tmp);
        @tmp=split(/\s+/,$what);
	$sub_func=shift(@tmp);
	$args="@tmp";

	Giraf::Core::debug("admin module : sub_func=$sub_func");

	switch ($sub_func)
	{
		case 'enable'           {       push(@return,bot_disable_module(0,$nick,$dest,$args)); }
		case 'disable'          {       push(@return,bot_disable_module(1,$nick,$dest,$args)); }
	}

	return @return;
}

sub bot_admin_user {
        my ($nick,$dest,$what)=@_;

        Giraf::Core::debug("Giraf::Admin::bot_admin_user()");

        my @return;
        my ($sub_func,$args,@tmp);
        @tmp=split(/\s+/,$what);
        $sub_func=shift(@tmp);
        $args="@tmp";

	Giraf::Core::debug("admin user : sub_func=$sub_func");

	switch ($sub_func)
	{
		case 'register'	{	push(@return,bot_register_user($nick,$dest)); 		}
		case 'ignore'	{       push(@return,bot_ignore_user($nick,$dest,$args)); 	}
		case 'unignore'	{       push(@return,bot_unignore_user($nick,$dest,$args)); 	}
	}

	return @return;
}


sub bot_disable_module {
	my ($disabled,$nick,$dest,$what) = @_;

	Giraf::Core::debug("Giraf::Admin::bot_disable_module()");

	my @return;
	my ($ligne,$chan,$module_name,@tmp);
	@tmp=split(/\s+/,$what);
	$chan=shift(@tmp);
	$module_name=shift(@tmp);

	if( $chan=~/#.*/ )
	{
		if(Giraf::Admin::is_user_chan_admin($nick,$chan) && $module_name ne 'core')
		{
			if(Giraf::Module::module_exists($module_name) && Giraf::Chan::known_chan($chan) )
			{
				my $mot;
				if(!$disabled)
				{
					$mot="activé";
				}
				else
				{
					$mot="desactivé";
				}
				my $sth=$_dbh->prepare("INSERT OR REPLACE INTO $_tbl_modules_access (module_name,chan_name,disabled) VALUES (?,?,?)");
				$sth->execute($module_name,$chan,$disabled);
				$_auth_modules->{$chan}->{$module_name}={disabled=>$disabled};
				$ligne={ action =>"MSG",dest=>$dest,msg=>'Module [c=red]'.$module_name.'[/c] '.$mot.' pour [c=green]'.$chan.'[/c]!'};
			}
			else
			{
				$ligne={ action =>"MSG",dest=>$dest,msg=>'Module [c=red]'.$module_name.'[/c] inconnu ou [c=green]'.$chan.'[/c] inconnu !'};
			}
			push (@return,$ligne);
		}
	}
	return @return;
}

sub bot_join {
	my ($nick,$dest,$what) = @_;

	Giraf::Core::debug("Giraf::Admin::bot_join()");

	my @return;
	my ($chan,$reason);

	$what=~m/^(#\S+?)$/;

	$chan=$1;
	if( Giraf::Admin::is_user_admin($nick) )
	{
		Giraf::Chan::join($chan);
	}
	return @return;
}

sub bot_part {
	my ($nick,$dest,$what) = @_;

	Giraf::Core::debug("Giraf::Admin::bot_part()");

	my @return;
	my ($chan,$reason,@tmp);
	@tmp=split(/\s+/,$what);
	$chan=shift(@tmp);
	$reason = "@tmp";
	
	if( $chan=~/#.*/ )
	{
		Giraf::Core::debug("part $chan, $reason");

		if( Giraf::Admin::is_user_admin($nick) )
		{
			Giraf::Chan::part($chan,$reason);
		}
	}
	return @return;
}

sub bot_register_user {
	my ($nick,$dest) = @_;

	Giraf::Core::debug("Giraf::Admin::bot_register_user($nick)");

	my @return;
	my $ligne;
	if(Giraf::User::user_register($nick))
	{
		$ligne={ action =>"MSG",dest=>$dest,msg=>'Utilisateur [c=red]'.Giraf::User::getUUID($nick).'[/c] enregistré !'};
	}
	else
	{
		$ligne={ action =>"MSG",dest=>$dest,msg=>'Impossible d\'enregistrer [c=red]'.Giraf::User::getUUID($nick).'[/c] !'};
	}
	push(@return,$ligne);	
	return @return;
}

sub bot_ignore_user {
	my ($nick,$dest,$args) = @_;

	Giraf::Core::debug("Giraf::Admin::bot_ignore_user()");

	my (@return, $ligne, @tmp, $who, $permanent);
	@tmp=split(/\s+/,$args);
	
	$who=shift(@tmp);
	$permanent=shift(@tmp);
	
	if($permanent eq "1")
	{
		$permanent=1;
	}
	else
	{
		$permanent=0;
	}

	Giraf::Core::debug("bot_ignore_user who=$who, perma=$permanent");
	
	if(Giraf::Admin::is_user_admin($nick) )
	{
		if(Giraf::User::user_ignore($who,$permanent))
		{
			$ligne={action => "MSG",dest=>$dest,msg=>"Utilisateur [c=red]".$who."[/c] ignoré ! (permanent=$permanent)"};
		}
		else
		{
			$ligne={ action =>"MSG",dest=>$dest,msg=>"Impossible d\'ignorer [c=red]".$who."[/c] !"};
		}
		push(@return,$ligne);
	}
	return @return;
}

sub bot_unignore_user {
        my ($nick,$dest,$args) = @_;

	Giraf::Core::debug("Giraf::Admin::bot_unignore_user()");

        my @return;
        my $ligne;
        $args=~m/^(.+?)\s*$/;
        my ($who)=($1);
        Giraf::Core::debug("bot_unignore_user who=$who");
        if( Giraf::Admin::is_user_admin($nick) )
        {
                if( Giraf::User::user_unignore($who) )
                {
                        $ligne={action => "MSG",dest=>$dest,msg=>"Utilisateur [c=red]".$who."[/c] unignoré !"};
                }
                push(@return,$ligne);
        }
        return @return;
}


#Admin user management subs
sub is_user_botadmin {
	my ($user) = @_;
	Giraf::Core::debug("Giraf::Admin::is_user_botadmin($user)");
	return Giraf::User::is_user_botadmin($user);
}

sub is_user_admin {
	my ($user) = @_;
	Giraf::Core::debug("Giraf::Admin::is_user_admin($user)");
	return Giraf::User::is_user_admin($user);
}

sub is_user_chan_admin {
	my ($user,$chan) = @_;
	Giraf::Core::debug("Giraf::Admin::is_user_chan_admin($user,$chan)");
	my ($uuid,$sth,$count);
	if(is_user_admin($user))
	{
		return 1;
	}
	else
	{
		$uuid=Giraf::User::getUUID($user);
		$sth=$_dbh->prepare("SELECT COUNT(*) FROM $_tbl_chan_admin WHERE chan_name LIKE ? AND user_UUID LIKE ?"); 
		$sth->bind_columns(\$count);
		$sth->execute($chan,$uuid);
		$sth->fetch();
		return $count;
	}
}

sub is_user_registered {
	my ($user) = @_;
	Giraf::Core::debug("Giraf::Admin::is_user_registered");
	return Giraf::User::is_user_registered($user);
}

#Admin utility subs
sub module_authorized {
	my ($module_name,$chan) = @_;
	Giraf::Core::debug("Giraf::Admin::module_authorized($module_name @ $chan)");
	return (!$_auth_modules->{$chan}->{$module_name}->{disabled});
}

sub module_authorized_update {

	Giraf::Core::debug("module_authorized_update()");

	undef $_auth_modules;

	my ($disabled,$module_name,$chan);
	my $sth=$_dbh->prepare("SELECT disabled,module_name,chan_name FROM $_tbl_modules_access");
	$sth->bind_columns(\$disabled,\$module_name,\$chan);
	$sth->execute();
	while($sth->fetch())
	{
		$_auth_modules->{$chan}->{$module_name}={disabled=>$disabled};
	}
}



#Admin user tracking subs
sub add_user_in_chan {
	my ($uuid,$chan) = @_;
	Giraf::Core::debug("Giraf::Admin::add_user_in_chan($uuid,$chan)");
	my $sth=$_dbh->prepare("INSERT OR REPLACE INTO $_tbl_users_in_chan (user_UUID,chan_name) VALUES (?,?)");
	return $sth->execute($uuid,$chan);
}

sub del_user_in_chan {
	my ($uuid,$chan) = @_;
	Giraf::Core::debug("Giraf::Admin::del_user_in_chan($uuid,$chan)");
	my $sth=$_dbh->prepare("DELETE FROM $_tbl_users_in_chan WHERE user_UUID LIKE ? AND chan_name LIKE ?");
	return $sth->execute($uuid,$chan);
}

sub del_user_in_all_chan {
	my ($uuid) = @_;
	Giraf::Core::debug("Giraf::Admin::del_user_in_all_chan($uuid)");
	my $sth=$_dbh->prepare("DELETE FROM $_tbl_users_in_chan WHERE user_UUID LIKE ?");
	return $sth->execute($uuid);
}

sub user_unregister {
	my ($uuid) = @_;
	my $sth=$_dbh->prepare("DELETE FROM $_tbl_chan_admin WHERE user_UUID LIKE ?");
	return $sth->execute($uuid);
}

1;
