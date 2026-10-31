#!/usr/bin/perl
# save_server.cgi
# Uloží zmeny nastavení servera. Zmeny, po ktorých treba nastaviť klientov znova,
# vyžadujú potvrdenie.

require './wireguard-lib.pl';
&error_setup($text{'edit_err'});
&ReadParse();

my $old = &get_server_settings();
&error($text{'err_server'}) if (!$old);

my %n;
foreach my $k ("port", "v4", "v6", "nic") {
	$n{$k} = defined($in{$k}) ? $in{$k} : "";
	$n{$k} =~ s/^\s+//;
	$n{$k} =~ s/\s+$//;
	}
$n{'nic'} = $old->{'nic'} if ($n{'nic'} eq "");
my $regen = $in{'regen'} ? 1 : 0;

my $err = &validate_setup(\%n);
&error($err) if ($err);

my @changes;
push(@changes, &text('edit_ch_port', $old->{'port'}, $n{'port'})) if ($old->{'port'} ne $n{'port'});
push(@changes, &text('edit_ch_v4', $old->{'v4'}, $n{'v4'})) if ($old->{'v4'} ne $n{'v4'});
push(@changes, &text('edit_ch_v6', $old->{'v6'} || "-", $n{'v6'} || "-")) if ($old->{'v6'} ne $n{'v6'});
push(@changes, &text('edit_ch_nic', $old->{'nic'} || "-", $n{'nic'})) if ($old->{'nic'} ne $n{'nic'});
push(@changes, $text{'edit_ch_key'}) if ($regen);
&error($text{'edit_nochange'}) if (!@changes);

my ($head, $peers) = &parse_conf();
my $affects = ($regen || $old->{'port'} ne $n{'port'} || $old->{'v4'} ne $n{'v4'} ||
	       $old->{'v6'} ne $n{'v6'}) ? 1 : 0;

# Zmeny, ktoré zneplatnia konfiguráciu klientov, treba potvrdiť
if ($affects && @$peers && !$in{'confirm'}) {
	&ui_print_header(undef, $text{'edit_title'}, "");
	print $text{'edit_confirm_intro'},"<ul>\n";
	print "<li>$_</li>\n" foreach (map { &html_escape($_) } @changes);
	print "</ul>\n";
	print &text('edit_confirm_clients', scalar(@$peers)),"<p>\n";
	print &ui_form_start("save_server.cgi", "post");
	foreach my $k (keys %n) {
		print &ui_hidden($k, $n{$k});
		}
	print &ui_hidden("regen", $regen);
	print &ui_hidden("confirm", 1);
	print &ui_form_end([ [ "go", $text{'edit_confirm_ok'} ] ]);
	&ui_print_footer("edit_server.cgi", $text{'edit_title'});
	exit;
	}

my ($steps, $ok, $aff) = &apply_server_edit(\%n, $regen);
&webmin_log("edit", "server", $config{'interface'});

&ui_print_header(undef, $text{'edit_title'}, "");
my %mark = ( 'ok' => "<b style='color:#2a8a2a'>[OK]</b>",
	     'warn' => "<b style='color:#c07000'>[!]</b>",
	     'err' => "<b style='color:#b22222'>[$text{'setup_error'}]</b>" );
print "<ul style='list-style:none;padding-left:0'>\n";
foreach my $s (@$steps) {
	print "<li>$mark{$s->[0]} $s->[1]</li>\n";
	}
print "</ul>\n";

if (!$ok) {
	print "<p><b>$text{'setup_failed'}</b></p>\n";
	}
elsif ($aff && @$peers) {
	print "<p><b>$text{'edit_regen_clients'}</b></p><ul>\n";
	foreach my $p (sort { $a->{'octet'} <=> $b->{'octet'} }
		       grep { defined($_->{'octet'}) } @$peers) {
		print "<li><a href='add_client.cgi?name=".&urlize($p->{'name'}).
		      "&octet=$p->{'octet'}'>".&html_escape($p->{'name'})."</a></li>\n";
		}
	print "</ul>\n";
	}
&ui_print_footer("", $text{'index_return'});
