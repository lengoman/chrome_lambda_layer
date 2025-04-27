FROM public.ecr.aws/lambda/provided:al2023 as builder

# Install build tools and dependencies
RUN microdnf update -y && \
    microdnf install -y \
    gcc \
    gcc-c++ \
    make \
    nspr \
    nspr-devel \
    nss \
    nss-softokn \
    nss-util \
    brotli \
    wget \
    tar \
    gzip \
    zip \
    shadow-utils \
    # Additional dependencies for Chromium headless operation
    libX11 \
    libXcomposite \
    alsa-lib \
    atk \
    at-spi2-atk \
    cairo \
    cups-libs \
    dbus-libs \
    expat \
    fontconfig \
    mesa-libgbm \
    libgcc \
    glib2 \
    gtk3 \
    pango \
    libstdc++ \
    libxcb \
    libXcursor \
    libXdamage \
    libXext \
    libXfixes \
    libXi \
    libXrandr \
    libXrender \
    libXScrnSaver \
    libXtst \
    && microdnf clean all

# Install Node.js
RUN curl -fsSL https://rpm.nodesource.com/setup_18.x | bash - && \
    microdnf install -y nodejs && \
    microdnf clean all

# Set working directory
WORKDIR /build

# Install Chromium package
RUN npm install @sparticuz/chromium@132.0.0

# Extract binaries
RUN mkdir -p /build/chromium && \
    cd /build/chromium && \
    brotli -d /build/node_modules/@sparticuz/chromium/bin/chromium.br -o chrome && \
    chmod +x chrome && \
    brotli -d /build/node_modules/@sparticuz/chromium/bin/al2023.tar.br -o al2023.tar && \
    brotli -d /build/node_modules/@sparticuz/chromium/bin/fonts.tar.br -o fonts.tar && \
    brotli -d /build/node_modules/@sparticuz/chromium/bin/swiftshader.tar.br -o swiftshader.tar && \
    tar xf al2023.tar && \
    tar xf fonts.tar && \
    tar xf swiftshader.tar && \
    rm *.tar

# Create NSS database directory and lib directory
RUN mkdir -p /build/chromium/etc/pki/nssdb && \
    mkdir -p /build/chromium/lib

# Build NSS from source
RUN echo "Building NSS from source..." && \
    cd /build && \
    wget https://ftp.mozilla.org/pub/security/nss/releases/NSS_3_97_RTM/src/nss-3.97.tar.gz && \
    tar xf nss-3.97.tar.gz && \
    cd nss-3.97/nss && \
    make nss_build_all && \
    # Copy built libraries
    cp -Lv dist/Linux*.obj/lib/*.so* /build/chromium/lib/ && \
    # Set permissions
    chmod 755 /build/chromium/lib/*.so* && \
    # Clean up
    cd /build && \
    rm -rf nss-3.97* && \
    # Verify library dependencies
    echo "Checking library dependencies..." && \
    ldd /build/chromium/chrome || true && \
    echo "Checking NSS library dependencies..." && \
    ldd /build/chromium/lib/libnss3.so || true && \
    # List all libraries
    echo "Listing all libraries..." && \
    ls -la /build/chromium/lib/

# Clean up unnecessary files
RUN rm -rf /build/node_modules

# Final stage
FROM public.ecr.aws/lambda/provided:al2023

# Install zip and shadow-utils
RUN microdnf install -y zip shadow-utils && microdnf clean all

# Copy the layer package
COPY --from=builder /build/chromium /opt/chromium

# Set up sandbox and permissions
RUN mkdir -p /opt/chromium/sandbox && \
    # Create chrome user and group
    echo "chrome:x:1000:1000:Chrome User:/opt/chromium:/bin/false" >> /etc/passwd && \
    echo "chrome:x:1000:" >> /etc/group && \
    # Set up sandbox directory permissions
    chown -R chrome:chrome /opt/chromium/sandbox && \
    chmod 4755 /opt/chromium/chrome && \
    chown root:root /opt/chromium/chrome && \
    # Set up library permissions
    chown -R chrome:chrome /opt/chromium/lib && \
    chmod 755 /opt/chromium/lib && \
    chmod 644 /opt/chromium/lib/*.so* && \
    # Set up NSS database permissions
    chown -R chrome:chrome /opt/chromium/etc/pki/nssdb && \
    chmod 700 /opt/chromium/etc/pki/nssdb

# Set environment variables
ENV CHROME_PATH=/opt/chromium/chrome
ENV LD_LIBRARY_PATH=/opt/chromium/lib:$LD_LIBRARY_PATH
ENV NSS_DB_PATH=/opt/chromium/etc/pki/nssdb
ENV CHROME_USER=chrome
ENV CHROME_GROUP=chrome

# Verify the final layer contents
RUN echo "Verifying final layer contents..." && \
    ls -la /opt/chromium/lib/ && \
    ldd /opt/chromium/chrome || true

# Create layer package
RUN cd /opt && \
    echo "Creating layer package..." && \
    ls -la chromium/lib/ && \
    cd chromium/lib && \
    # Create a list of all symlinks and their targets
    for f in $(find . -type l); do \
        target=$(readlink $f); \
        echo "$f -> $target"; \
    done && \
    cd /opt && \
    # Create the zip file with symlinks preserved
    zip -y -r9 /chromium-layer.zip chromium/ && \
    echo "Verifying layer package contents..." && \
    unzip -l /chromium-layer.zip | grep -E "libnss|libnspr"
