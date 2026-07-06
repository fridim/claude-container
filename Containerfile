ARG FEDORA_VERSION=latest

FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION}

RUN dnf install -y \
    bubblewrap \
    socat \
    nodejs \
    rustup \
    && dnf clean all

RUN curl --silent --location \
    https://github.com/Orange-OpenSource/hurl/releases/download/7.1.0/hurl-7.1.0-x86_64-unknown-linux-gnu.tar.gz \
    | tar xvz -C /tmp/ \
    && mv /tmp/hurl-*/bin/* /usr/local/bin/ \
    && rm -rf /tmp/hurl-*

# jj (Jujutsu) — Git-compatible VCS
ARG JJ_VERSION=0.42.0
RUN curl --silent --location \
    "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/jj-v${JJ_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar xz --strip-components=0 -C /usr/local/bin/ ./jj

COPY packages.txt /opt/packages.txt
RUN dnf install -y $(cat /opt/packages.txt) \
    && dnf clean all

# Android SDK: cmdline-tools, platforms, build-tools, platform-tools
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708
RUN mkdir -p /opt/android-sdk/cmdline-tools \
    && curl --silent --location \
       "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
       -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /opt/android-sdk/cmdline-tools \
    && mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/opt/android-sdk \
       "platforms;android-35" "build-tools;36.0.0" "platform-tools" \
    && chmod -R a+rw /opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_USER_HOME=/home/claude/.android

# Gradle
ARG GRADLE_VERSION=9.5.1
RUN curl --silent --location \
       "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
       -o /tmp/gradle.zip \
    && unzip -qo /tmp/gradle.zip -d /opt \
    && rm /tmp/gradle.zip

COPY settings.json /etc/claude-code/managed-settings.json

RUN npm install -g @googleworkspace/cli
RUN go install github.com/ankitpokhrel/jira-cli/cmd/jira@latest \
    && mv /root/go/bin/jira /usr/local/bin/jira

ARG UID=1000
ARG GID=1000
RUN groupadd -g "${GID}" claude 2>/dev/null || true
RUN useradd -u "${UID}" -g "${GID}" -m claude
COPY sudoers /etc/sudoers.d/claude
# Rust
RUN su - claude -c "rustup-init -y --default-toolchain stable --profile default" \
    && su - claude -c "source /home/claude/.cargo/env && rustup component add rustfmt clippy"
# Install uv (modern Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
#
USER ${UID}:${GID}
ENV BASH_ENV=/home/claude/.bash_environment
COPY environment $BASH_ENV

ENV PATH=/home/claude/.local/bin:/opt/gradle-9.5.1/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/local/bin:/usr/bin
ARG VERSION=stable
RUN curl -fsSL --proto-redir '-all,https' --tlsv1.3 https://claude.ai/install.sh | bash -s "${VERSION}"

RUN mkdir -p /home/claude/.config/jj
WORKDIR /projects
ENV CLAUDE_CODE_USE_VERTEX=1 CLOUD_ML_REGION=global DISABLE_AUTOUPDATER=1
ENTRYPOINT ["/home/claude/.local/bin/claude"]
