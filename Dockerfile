# Dockerfile for BYOH Provisioner - Prow CI Container Image
# This image includes all dependencies needed to run the provisioner in CI

FROM registry.ci.openshift.org/ocp/4.17:cli AS builder

# Install dependencies first
RUN yum install -y \
    unzip \
    jq \
    git \
    bash \
    which \
    && yum clean all

# Install Terraform
ARG TERRAFORM_VERSION=1.9.5
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip \
    && terraform version

FROM registry.ci.openshift.org/ocp/4.17:cli

# Copy Terraform from builder
COPY --from=builder /usr/local/bin/terraform /usr/local/bin/terraform

# Install runtime dependencies
RUN yum install -y \
    jq \
    bash \
    which \
    && yum clean all

# Set working directory
WORKDIR /usr/local/share/byoh-provisioner

# Copy provisioner scripts
COPY byoh.sh ./byoh.sh
COPY lib/ ./lib/
COPY configs/ ./configs/
COPY aws/ ./aws/
COPY azure/ ./azure/
COPY gcp/ ./gcp/
COPY vsphere/ ./vsphere/
COPY nutanix/ ./nutanix/
COPY none/ ./none/

# Make byoh.sh executable and create symlink in PATH
RUN chmod +x ./byoh.sh && ln -s /usr/local/share/byoh-provisioner/byoh.sh /usr/local/bin/byoh.sh

# Set environment variables for CI
ENV BYOH_TMP_DIR=/tmp/terraform_byoh
ENV CI=true

# Verify installations
RUN terraform version && \
    oc version --client && \
    jq --version && \
    ./byoh.sh help

# Default command
ENTRYPOINT ["/usr/local/bin/byoh.sh"]
CMD ["help"]
