# Dockerfile for BYOH Provisioner - Prow CI Container Image
# This image includes all dependencies needed to run the provisioner in CI

FROM registry.ci.openshift.org/ocp/4.17:cli AS builder

# Install Terraform
ARG TERRAFORM_VERSION=1.9.5
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip \
    && terraform version

# Install additional dependencies
RUN yum install -y \
    jq \
    git \
    bash \
    which \
    && yum clean all

FROM registry.ci.openshift.org/ocp/4.17:cli

# Copy Terraform from builder
COPY --from=builder /usr/local/bin/terraform /usr/local/bin/terraform

# Install runtime dependencies
RUN yum install -y \
    jq \
    bash \
    which \
    && yum clean all

# Copy provisioner scripts
COPY byoh.sh /usr/local/bin/byoh.sh
COPY lib/ /usr/local/lib/byoh-provisioner/lib/
COPY configs/ /usr/local/share/byoh-provisioner/configs/
COPY aws/ /usr/local/share/byoh-provisioner/aws/
COPY azure/ /usr/local/share/byoh-provisioner/azure/
COPY gcp/ /usr/local/share/byoh-provisioner/gcp/
COPY vsphere/ /usr/local/share/byoh-provisioner/vsphere/
COPY nutanix/ /usr/local/share/byoh-provisioner/nutanix/
COPY none/ /usr/local/share/byoh-provisioner/none/

# Make byoh.sh executable
RUN chmod +x /usr/local/bin/byoh.sh

# Set working directory
WORKDIR /usr/local/share/byoh-provisioner

# Set environment variables for CI
ENV BYOH_TMP_DIR=/tmp/terraform_byoh
ENV CI=true

# Verify installations
RUN terraform version && \
    oc version --client && \
    jq --version && \
    /usr/local/bin/byoh.sh help

# Default command
ENTRYPOINT ["/usr/local/bin/byoh.sh"]
CMD ["help"]
