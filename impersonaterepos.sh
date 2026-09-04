PNUM=860228474942
POOL="projects/$PNUM/locations/global/workloadIdentityPools/github-pool"
for REPO in backend-project frontend-project; do
  gcloud iam service-accounts add-iam-policy-binding \
    github-deployer@project-f0ad4dfa-b194-4dc6-963.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/$POOL/attribute.repository/csanyilevente8/$REPO" \
    --project=project-f0ad4dfa-b194-4dc6-963
done
