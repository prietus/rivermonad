# The icon font of waymobar in rivermonad-dotfiles. Fedora has Material
# Icons (material-icons-fonts) but not Material Symbols, the variable font.

%global commit      10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global commitdate  20261023

Name:           material-symbols-rounded-fonts
Version:        0^%{commitdate}git%{shortcommit}
Release:        1%{?dist}
Summary:        Material Symbols Rounded, Google's variable icon font

License:        Apache-2.0
URL:            https://github.com/google/material-design-icons
Source0:        https://raw.githubusercontent.com/google/material-design-icons/%{commit}/variablefont/MaterialSymbolsRounded%%5BFILL,GRAD,opsz,wght%%5D.ttf#/MaterialSymbolsRounded.ttf
Source1:        https://raw.githubusercontent.com/google/material-design-icons/%{commit}/LICENSE#/material-symbols-LICENSE

BuildArch:      noarch
BuildRequires:  fonts-rpm-macros
Requires:       fontpackages-filesystem

%description
Material Symbols are Google's icons as a variable font, with fill, weight,
grade and optical size axes. This package has the Rounded cut, "Material
Symbols Rounded", used by the waymobar configuration of rivermonad-dotfiles.


%prep
cp -p %{SOURCE1} LICENSE


%build


%install
install -Dpm 0644 %{SOURCE0} %{buildroot}%{_fontdir}/MaterialSymbolsRounded.ttf


%files
%license LICENSE
%{_fontdir}/


%changelog
* Mon Nov 23 2026 Carlos Prieto Ortiz <prietus@live.com> - 0^20261023git10ecc14-1
- First package
