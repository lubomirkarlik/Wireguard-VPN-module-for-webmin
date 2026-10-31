#!/usr/bin/perl
# add_client.cgi
# Formulár na pridanie klienta (alebo pregenerovanie kľúčov existujúceho)

require './wireguard-lib.pl';
&ReadParse();
&ui_print_header(undef, $text{'add_title'}, "");

my $srv = &get_server();
&error($text{'err_server'}) if (!$srv);
my ($head, $peers) = &parse_conf();
my $octet = $in{'octet'} ne "" ? $in{'octet'} : &next_free_octet($peers);

print &ui_form_start("save_client.cgi", "post");
print &ui_table_start($text{'add_title'}, "width=100%", 2);
print &ui_table_row($text{'add_name'}, &ui_textbox("name", $in{'name'}, 25));
print &ui_table_row($text{'add_ip'},
	"<tt>".$srv->{'v4net'}.".</tt>".&ui_textbox("octet", $octet, 4));
print &ui_table_end();
print &ui_form_end([ [ "create", $text{'add_create'} ] ]);

&ui_print_footer("", $text{'index_return'});
