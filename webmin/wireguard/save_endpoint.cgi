#!/usr/bin/perl
# save_endpoint.cgi
# Uloží verejnú adresu (WAN) používanú v konfigurácii nových klientov

require './wireguard-lib.pl';
&error_setup($text{'endpoint_err'});
&ReadParse();

my $e = $in{'endpoint'};
$e =~ s/^\s+//;
$e =~ s/\s+$//;
&error($text{'err_endpoint'}) if ($e !~ /^[A-Za-z0-9._:\[\]-]+$/);
&save_endpoint($e);
&webmin_log("endpoint", undef, $e);
&redirect("");
