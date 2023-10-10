echo "### "
echo "### Begin Tools check"
echo "### "

## Install Tools
mkdir -p $WORK_DIR/bin

## Install Istio
if command -v istioctl 2>/dev/null; then
	echo "Istio already installed."
else
	echo "Downloading Istio..."
	curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.19.1 TARGET_ARCH=x86_64 sh -
	cp istio-$ISTIO_VERSION/bin/istioctl $WORK_DIR/bin/.
    mv istio-$ISTIO_VERSION $WORK_DIR/
	echo "Istio installation complete."
fi

## Install kubectl
if command -v kubectl 2>/dev/null; then
	echo "kubectl already installed."
else
	echo "Please install kubectl"
    exit 1
fi

## Install kubectl
if command -v az 2>/dev/null; then
	echo "AZ client already installed."
else
	echo "Please install az client"
    exit 1
fi

echo "### "
echo "### Tools check complete"
echo "### "