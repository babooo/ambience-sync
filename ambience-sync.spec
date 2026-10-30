# Nothing here needs stripping or compressing, and the device's BusyBox xargs
# breaks rpm's brp scripts, so skip them
%global __os_install_post %{nil}

Name:       ambience-sync
Summary:    Match Android's colors and dark/light theme to the Sailfish ambience
Version:    1.1.0
Release:    1
License:    MIT
BuildArch:  noarch
URL:        https://github.com/babooo/ambience-sync
Source0:    %{name}-%{version}.tar.gz

%description
Adds an "Android theme" page under Settings > Look and feel. It can use
the highlight color of the current ambience as the Android system color
and switch Android between its dark and light theme to match the ambience.
A small background service applies changes when the ambience or a setting
changes, and again whenever AppSupport starts. 

%prep
%setup -q -c -n %{name}-%{version}

%build

%install
rm -rf %{buildroot}
install -d %{buildroot}/usr/libexec/ambience-sync
install -m 0755 apply.sh %{buildroot}/usr/libexec/ambience-sync/apply.sh
install -m 0755 watch.sh %{buildroot}/usr/libexec/ambience-sync/watch.sh
install -m 0755 on-appsupport-start.sh %{buildroot}/usr/libexec/ambience-sync/on-appsupport-start.sh
install -d %{buildroot}/etc/systemd/system
install -m 0644 ambience-sync.service %{buildroot}/etc/systemd/system/ambience-sync.service
install -m 0644 ambience-sync-android.service %{buildroot}/etc/systemd/system/ambience-sync-android.service
install -d %{buildroot}/usr/share/jolla-settings/entries
install -m 0644 ambience-sync.json %{buildroot}/usr/share/jolla-settings/entries/ambience-sync.json
install -d %{buildroot}/usr/share/jolla-settings/pages/ambience-sync
install -m 0644 ambience-sync.qml %{buildroot}/usr/share/jolla-settings/pages/ambience-sync/ambience-sync.qml
for scale in z1.0 z1.25 z1.5 z1.5-large z1.75 z2.0 z2.5; do
    for sub in icons icons-monochrome; do
        install -d %{buildroot}/usr/share/themes/sailfish-default/silica/$scale/$sub
        install -m 0644 icons/$scale/icon-m-ambience-sync.png %{buildroot}/usr/share/themes/sailfish-default/silica/$scale/$sub/icon-m-ambience-sync.png
    done
done

%files
%defattr(-,root,root,-)
%dir /usr/libexec/ambience-sync
/usr/libexec/ambience-sync/apply.sh
/usr/libexec/ambience-sync/watch.sh
/usr/libexec/ambience-sync/on-appsupport-start.sh
/etc/systemd/system/ambience-sync.service
/etc/systemd/system/ambience-sync-android.service
/usr/share/jolla-settings/entries/ambience-sync.json
%dir /usr/share/jolla-settings/pages/ambience-sync
/usr/share/jolla-settings/pages/ambience-sync/ambience-sync.qml
/usr/share/themes/sailfish-default/silica/z*/icons*/icon-m-ambience-sync.png

%pre
VER=$(rpm -qa | sed -n 's/^appsupport\([0-9][0-9]*\)-system-.*/\1/p' | sort -n | tail -n1)
if [ -z "$VER" ]; then
    echo "ambience-sync needs Android AppSupport, which is not installed." >&2
    exit 1
fi
if [ "$VER" -lt 13 ]; then
    echo "ambience-sync needs Android 13 or newer (found Android $VER)." >&2
    exit 1
fi

%posttrans
systemctl daemon-reload || :
systemctl enable ambience-sync.service || :
systemctl enable ambience-sync-android.service || :
systemctl restart ambience-sync.service || :

%preun
if [ "$1" = 0 ]; then
    systemctl disable ambience-sync-android.service || :
    systemctl disable --now ambience-sync.service || :
    # give the person their default Android colors back
    /usr/libexec/ambience-sync/apply.sh --reset || :
fi

%postun
systemctl daemon-reload || :
