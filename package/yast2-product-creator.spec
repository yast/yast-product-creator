#
# spec file for package yast2-product-creator
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-product-creator
Version:        3.1.3
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Group:          System/YaST
License:        GPL-2.0
BuildRequires:	perl-XML-Writer update-desktop-files yast2-testsuite yast2-packager autoyast2-installation yast2-security yast2-add-on-creator yast2 yast2-slp
BuildRequires:  yast2-devtools >= 3.1.10

PreReq:         %fillup_prereq

Requires:	autoyast2-installation yast2-security yast2-country

# ag_pattern handling gzipped files
Requires:	yast2-add-on-creator >= 2.17.1

# SourceDialogs::IsPlainDir()
Requires:	yast2-packager >= 2.16.20

# changes in ag_anyxml agent
# Wizard_hw drop
# Wizard::SetDesktopTitleAndIcon
Requires:	yast2 >= 2.21.22

# Pkg::SourceForceRefreshNow()
Requires:	yast2-pkg-bindings >= 2.17.6

# New API of StorageDevices.ycp
Conflicts:      yast2-storage < 2.16.1

# prefer to install package with real templates
Recommends:	kiwi-config-openSUSE

BuildArchitectures:	noarch

Requires:       yast2-ruby-bindings >= 1.0.0

Summary:	YaST2 - Module for Creating New Products

%description
A wizard for creating your own product (installation images, live ISO,
XEN images etc.), based on existing installation sources.

%prep
%setup -n %{name}-%{version}

%build
%yast_build

%install
%yast_install

install -d $RPM_BUILD_ROOT/var/lib/YaST2/product-creator


%post
%{fillup_only -n product-creator}

%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/product-creator
%{yast_yncludedir}/product-creator/*
%{yast_clientdir}/product-creator.rb
%{yast_clientdir}/image-creator.rb
%{yast_clientdir}/kiwi.rb
%{yast_moduledir}/*.rb
%{yast_desktopdir}/product-creator.desktop
%{yast_desktopdir}/image-creator.desktop
%{yast_ybindir}/y2mkiso
%doc %{yast_docdir}
%doc %{yast_docdir}/README.expert

%dir %{yast_ydatadir}/product-creator
%{yast_ydatadir}/product-creator/*
#%dir /etc/YaST2/product-creator
%{yast_scrconfdir}/*.scr
/var/adm/fillup-templates/sysconfig.product-creator
