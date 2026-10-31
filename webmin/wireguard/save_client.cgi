#!/usr/bin/perl
# save_client.cgi
# Vytvorí klienta (alebo pregeneruje kľúče existujúceho) a zobrazí QR kód

require './wireguard-lib.pl';
&error_setup($text{'save_err'});
&ReadParse();

my $name = $in{'name'};
my $octet = $in{'octet'};
$name =~ s/^\s+//;
$name =~ s/\s+$//;
$octet =~ s/^\s+//;
$octet =~ s/\s+$//;

my ($head, $peers) = &parse_conf();
my $err = &validate_client($name, $octet, $peers);
&error($err) if ($err);

# Existujúca IP: pregenerovanie zneplatní starého klienta, treba potvrdenie
my $old = &find_peer($peers, $octet);
if ($old && !$in{'confirm'}) {
	&ui_print_header(undef, $text{'save_title'}, "");
	print &text('save_exists', "<tt>".&html_escape($old->{'allowed'})."</tt>",
		    "<b>".&html_escape($old->{'name'})."</b>"),"<p>\n";
	print &ui_form_start("save_client.cgi", "post");
	print &ui_hidden("name", $name);
	print &ui_hidden("octet", $octet);
	print &ui_hidden("confirm", 1);
	print &ui_form_end([ [ "go", $text{'save_confirm'} ] ]);
	&ui_print_footer("", $text{'index_return'});
	exit;
	}

my $res = &create_client($name, $octet);
&webmin_log($old ? "regen" : "create", "client", $name);

&ui_print_header(undef, $text{'save_title'}, "");
print &text('save_done', "<b>".&html_escape($name)."</b>",
	    "<tt>".&html_escape($res->{'ip'})."</tt>"),"<p>\n";
if ($res->{'warn'}) {
	print "<b>".&text('save_warn', &html_escape($res->{'warn'}))."</b><p>\n";
	}
elsif (!&interface_up()) {
	print $text{'save_down'},"<p>\n";
	}

print "<b>$text{'save_secret'}</b><p>\n";

my $png = &qr_png_base64($res->{'conf'});
if ($png) {
	print "<p>",&text('save_scan', "<b>".&html_escape($name)."</b>"),"</p>\n";
	print "<img alt='QR' style='image-rendering:pixelated;background:#fff;padding:4px' ",
	      "src='data:image/png;base64,$png'><p>\n";
	}
else {
	print "<i>".&text('save_noqr', "<tt>$config{'qrencode'}</tt>")."</i><p>\n";
	}

my $b64 = &encode_base64($res->{'conf'}, "");
print "<a href='data:text/plain;charset=utf-8;base64,$b64' ",
      "download='".&html_escape($name).".conf'>$text{'save_download'}</a><p>\n";
print &ui_textarea("conf", $res->{'conf'}, 12, 70, "off", 0,
		   "readonly style='font-family:monospace'"),"<p>\n";

&ui_print_footer("", $text{'index_return'});
