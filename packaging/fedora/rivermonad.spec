# Haskell packaging guidelines:
# https://docs.fedoraproject.org/en-US/packaging-guidelines/Haskell/

%global pkg_name rivermonad
%global pkgver %{pkg_name}-%{version}
%bcond_without tests
%{?haskell_setup}

Name:           %{pkg_name}
Version:        0.4.3
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
Suggests:       rivermonad-dotfiles

%description
rivermonad brings xmonad's model (StackSet, layouts, manage hooks and a
Haskell configuration file) to Wayland. It runs as the window manager
process of river >= 0.4 and talks to it through the
river-window-management-v1 protocol, implemented in pure Haskell.

This package also installs a "river + rivermonad" session for display
managers.


%package dotfiles
Summary:        A complete river + rivermonad desktop
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}
Requires:       waymobar >= 0.5.0
Requires:       bgmonad
Requires:       hasklets
Requires:       shotlet >= 0.1.1
# Lock screen, idle, Super+Shift+L.
Requires:       locklet
Requires:       polkit-gnome
Requires:       cliphist
Requires:       gammastep
Requires:       geoclue2
Requires:       foot
Requires:       fuzzel
Requires:       mako
Requires:       kanshi
Requires:       libnotify
# shot, screenrec
Requires:       grim
Requires:       slurp
Requires:       swappy
Requires:       wl-clipboard
Requires:       wf-recorder
# emoji
Requires:       wtype
Requires:       unicode-emoji
# Volume keys (wpctl).
Requires:       wireplumber
Requires:       xdg-desktop-portal-wlr
Requires:       xdg-desktop-portal-gtk
Requires:       rsms-inter-fonts
Requires:       google-noto-color-emoji-fonts
Requires:       material-symbols-rounded-fonts
# Ubuntu Mono derivative Powerline, the font of foot.ini.
Recommends:     powerline-fonts
# Location for the weather (rivermonad.hs starts its demo agent).
Recommends:     geoclue2
# Dark GTK themes set by rivermonad-setup (gsettings).
Recommends:     glib2
# The browser on Super+B.
Suggests:       firefox

%description dotfiles
The desktop of examples/dotfiles: the waymobar bar, the bgmonad living
wallpaper, hasklets widgets, shotlet screenshots, locklet, notifications,
a launcher and an emoji picker. A package does not write in your home, so
the files are installed in %{_datadir}/%{name}/dotfiles: run
rivermonad-setup as your user to copy them to ~/.config.


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
# geoclue's demo agent is in libexec on Fedora.
sed -i 's|/usr/lib/geoclue-2.0/demos/agent|%{_libexecdir}/geoclue-2.0/demos/agent|' \
  examples/dotfiles/config/rivermonad/rivermonad.hs


%build
%ghc_lib_build


%install
%ghc_lib_install

install -Dpm 0755 contrib/session/river-session %{buildroot}%{_bindir}/river-session
install -Dpm 0755 contrib/session/init %{buildroot}%{_datadir}/%{name}/init
mkdir -p %{buildroot}%{_datadir}/wayland-sessions
sed 's|@BINDIR@|%{_bindir}|' contrib/session/rivermonad.desktop \
  > %{buildroot}%{_datadir}/wayland-sessions/%{name}.desktop

# rivermonad-dotfiles. The build scripts compile against a source
# checkout; with the packaged libraries plain ghc is used.
mkdir -p %{buildroot}%{_datadir}/%{name}/dotfiles
cp -pr examples/dotfiles/config examples/dotfiles/local \
  %{buildroot}%{_datadir}/%{name}/dotfiles/
rm %{buildroot}%{_datadir}/%{name}/dotfiles/config/{rivermonad,waymobar,bgmonad}/build
install -Dpm 0755 examples/dotfiles/install.sh %{buildroot}%{_bindir}/rivermonad-setup


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


%files dotfiles
%license LICENSE
%doc examples/dotfiles/README.md
%{_bindir}/rivermonad-setup
%{_datadir}/%{name}/dotfiles/


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
* Mon Nov 23 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.4.3-1
- IPC: the state lists every window (for task bars); FocusWindow brings a
  minimised window to the current workspace
- rivermonad-dotfiles: waymobar 0.5.0's task bar

* Mon Nov 23 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.4.2-1
- rivermonad-dotfiles: clipboard history (cliphist, Super+C) and a night
  light (gammastep located by GeoClue, Super+Shift+N)

* Mon Nov 23 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.4.1-1
- rivermonad-dotfiles: waymobar 0.4.0's notifications widget and on-screen
  display; mako's "do not disturb" mode

* Mon Nov 23 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.4.0-1
- IPC: workspaces, the focused window, layout messages, windows by app id,
  title or identifier, Spawn, and named actions (ipcActions, "Actions")
- addDescrKeysP registers every described key as an IPC action
- rivermonad-dotfiles starts a polkit agent (polkit-gnome)

* Mon Nov 23 2026 Carlos Prieto Ortiz <prietus@live.com> - 0.3.0-2
- rivermonad-dotfiles subpackage, as in the Arch PKGBUILD

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
