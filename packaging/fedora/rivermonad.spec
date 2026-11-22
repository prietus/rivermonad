# Haskell packaging guidelines:
# https://docs.fedoraproject.org/en-US/packaging-guidelines/Haskell/

%global pkg_name rivermonad
%global pkgver %{pkg_name}-%{version}
%bcond_without tests
%{?haskell_setup}

Name:           %{pkg_name}
Version:        0.3.0
Release:        1%{?dist}
Summary:        Xmonad-style tiling window manager for the river Wayland compositor

License:        BSD-3-Clause
URL:            https://github.com/prietus/rivermonad
Source0:        %{url}/archive/v%{version}/%{pkgver}.tar.gz

BuildRequires:  ghc-rpm-macros
BuildRequires:  ghc-Cabal-devel
BuildRequires:  ghc-base-devel
BuildRequires:  ghc-binary-devel
BuildRequires:  ghc-bytestring-devel
BuildRequires:  ghc-containers-devel
BuildRequires:  ghc-directory-devel
BuildRequires:  ghc-filepath-devel
BuildRequires:  ghc-mtl-devel
BuildRequires:  ghc-network-devel
BuildRequires:  ghc-process-devel
BuildRequires:  ghc-text-devel
BuildRequires:  ghc-unix-devel
%if %{with ghc_prof}
BuildRequires:  ghc-base-prof
BuildRequires:  ghc-binary-prof
BuildRequires:  ghc-bytestring-prof
BuildRequires:  ghc-containers-prof
BuildRequires:  ghc-directory-prof
BuildRequires:  ghc-filepath-prof
BuildRequires:  ghc-mtl-prof
BuildRequires:  ghc-network-prof
BuildRequires:  ghc-process-prof
BuildRequires:  ghc-text-prof
BuildRequires:  ghc-unix-prof
%endif
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  desktop-file-utils

# ~/.config/rivermonad/rivermonad.hs is compiled at run time with ghc,
# against the library (like xmonad).
Requires:       ghc-%{name}-devel%{?_isa} = %{version}-%{release}
Requires:       river >= 0.4
Recommends:     foot
Recommends:     fuzzel
Recommends:     kanshi
Recommends:     libnotify

%description
rivermonad brings xmonad's model (StackSet, layouts, manage hooks and a
Haskell configuration file) to Wayland. It runs as the window manager
process of river >= 0.4 and talks to it through the
river-window-management-v1 protocol, implemented in pure Haskell.

This package also installs a "river + rivermonad" session for display
managers.


%package -n ghc-%{name}
Summary:        Haskell %{name} library

%description -n ghc-%{name}
This package provides the Haskell %{name} shared library.


%package -n ghc-%{name}-devel
Summary:        Haskell %{name} library development files
Provides:       ghc-%{name}-static = %{version}-%{release}
Provides:       ghc-%{name}-static%{?_isa} = %{version}-%{release}
%if %{defined ghc_version}
Requires:       ghc-compiler = %{ghc_version}
%endif
Requires:       ghc-%{name}%{?_isa} = %{version}-%{release}
Requires:       ghc-network-devel%{?_isa}
Requires:       pkgconfig(xkbcommon)

%description -n ghc-%{name}-devel
This package provides the Haskell %{name} library development files,
needed to compile the rivermonad configuration.


%if %{with haddock}
%package -n ghc-%{name}-doc
Summary:        Haskell %{name} library documentation
BuildArch:      noarch
Requires:       ghc-filesystem

%description -n ghc-%{name}-doc
This package provides the Haskell %{name} library documentation.
%endif


%if %{with ghc_prof}
%package -n ghc-%{name}-prof
Summary:        Haskell %{name} profiling library
Requires:       ghc-%{name}-devel%{?_isa} = %{version}-%{release}
Supplements:    (ghc-%{name}-devel and ghc-prof)

%description -n ghc-%{name}-prof
This package provides the Haskell %{name} profiling library.
%endif


%prep
%autosetup -n %{pkgver}


%build
%ghc_lib_build


%install
%ghc_lib_install

install -Dpm 0755 contrib/session/river-session %{buildroot}%{_bindir}/river-session
install -Dpm 0755 contrib/session/init %{buildroot}%{_datadir}/%{name}/init
mkdir -p %{buildroot}%{_datadir}/wayland-sessions
sed 's|@BINDIR@|%{_bindir}|' contrib/session/rivermonad.desktop \
  > %{buildroot}%{_datadir}/wayland-sessions/%{name}.desktop


%check
%if %{with tests}
%cabal_test
%endif
desktop-file-validate %{buildroot}%{_datadir}/wayland-sessions/%{name}.desktop


%files
%license LICENSE
%doc README.md examples/dotfiles
%{_bindir}/%{name}
%{_bindir}/river-session
%{_datadir}/%{name}/init
%{_datadir}/%{pkgver}/
%{_datadir}/wayland-sessions/%{name}.desktop


%files -n ghc-%{name} -f ghc-%{name}.files
%license LICENSE


%files -n ghc-%{name}-devel -f ghc-%{name}-devel.files


%if %{with haddock}
%files -n ghc-%{name}-doc -f ghc-%{name}-doc.files
%license LICENSE
%endif


%if %{with ghc_prof}
%files -n ghc-%{name}-prof -f ghc-%{name}-prof.files
%endif


%changelog
* Sun Nov 22 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.3.0-1
- 25 new contrib modules: WindowGo, WindowBringer, Navigation2D, Minimize,
  CopyWindow, SpawnOn, UpdatePointer, MostRecentlyUsed, Submap, RefocusLast,
  OnPropertyChange, WorkspaceHistory, WindowSwallowing, NamedActions, Dmenu,
  BinarySpacePartition, TwoPane, Magnifier, Maximize, LimitWindows,
  MultiToggle, CenteredIfSingle, CenteredMaster
- examples/dotfiles use them; rivermonad-setup sets dark GTK themes

* Sat Nov 14 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.2.0-1
- IPC "Windows" request; new floats bigger than the screen are shrunk
- examples/dotfiles: bgmonad, hasklets, shotlet, waymobar calendar; rivermonad-setup

* Mon Nov 09 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.1.0-1
- First release
