helm uninstall apiclarity -n apiclarity

kubectl delete ns apiclarity

kubectl delete -f https://raw.githubusercontent.com/microservices-demo/microservices-demo/master/deploy/kubernetes/complete-demo.yaml

# kubectl delete ns sock-shop

#helm uninstall --namespace istio-system --repo https://kiali.org/helm-charts kiali-server kiali-server

#kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/addons/prometheus.yaml

istioctl x uninstall --purge -y


