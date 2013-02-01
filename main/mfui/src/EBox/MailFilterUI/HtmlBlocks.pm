# Copyright (C) 2013 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
use strict;
use warnings;

# Interface class EBox::HtmlBlocks, it should be implemented by CGI namespaces
#
# This file defines the interface and gives the implementation for the EBox
# namespace
package EBox::MailFilterUI::HtmlBlocks;
use base 'EBox::HtmlBlocks';

use EBox::Gettext;
use EBox::Global;
use EBox::MailFilterUI::Menu;

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    bless($self, $class);
    return $self;
}

# Method: title
#
#       Returns the html code for the title
#
# Returns:
#
#       string - containg the html code for the title
#
sub title
{
    my $global = EBox::Global->getInstance();
    my $image_title = $global->theme()->{'image_title'};

    return EBox::Html::makeHtml('mfui/headTitle.mas',
                                image_title => $image_title);
}

# Method: menu
#
#       Returns the html code for the menu
#
# Returns:
#
#       string - containg the html code for the menu
#
sub menu
{
    my ($self, $current) = @_;

    my $root = EBox::MailFilterUI::Menu::menu($current);
    return $root->html;
}

1;