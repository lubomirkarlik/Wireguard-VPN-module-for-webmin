#!/usr/bin/perl
# service.cgi
# Štart, stop, reštart a spúšťanie pri štarte služby wg-quick

require './wireguard-lib.pl';
&error_setup($text{'service_err'});
&ReadParse();

&error($text{'service_bad'}) if ($in{'action'} !~ /^(start|stop|restart|enable|disable)$/);
&has_command("systemctl") || &error(&text('service_nosystemctl', "<tt>systemctl</tt>"));
my $err = &service_action($in{'action'});
&error(&html_escape($err)) if ($err);
&webmin_log("service", undef, $in{'action'});
&redirect("");
