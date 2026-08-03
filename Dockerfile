# Test environment for install.sh / dotfiles.sh.
#
# Deliberately NOT a faithful copy of the real machine: there's no systemd as
# PID 1, no hardware, no graphical session. See the README's "What the
# container cannot test" section for what still needs manual validation.

FROM archlinux:base-devel

# Refresh the package databases once at build time so the script's own
# `pacman -Syu` has something current to work with.
RUN pacman -Syu --noconfirm --needed \
        git sudo which \
    && pacman -Scc --noconfirm

# Non-root user with passwordless sudo: install.sh refuses to run as root
# and escalates with sudo at specific points.
RUN useradd -m -G wheel -s /bin/bash tester \
    && echo 'tester ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/tester \
    && chmod 0440 /etc/sudoers.d/tester \
    && install -d -o tester -g tester /home/tester/linux-setup

USER tester
WORKDIR /home/tester/linux-setup

# The repo is bind-mounted (or copied) at run time by test.sh.
CMD ["/bin/bash"]
