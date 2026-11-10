# Shrublab privacy policy

The public policy is served at `https://shrublab.xyz/privacy` (also accepting a
trailing slash). Its source is `modules/web/_pages/privacy.html`. The edge serves
that file directly from the Nix store through the existing ingress aspect. Other
apex paths continue to redirect to Authentik; no application, database, cookies or
external assets are needed to read the policy.

The current Google integration is Inbox Zero. Other applications must not be
presented as receiving Gmail data merely because they share Shrublab branding or
a Google project. Review the policy before adding integrations or changing scopes.
The public contact is `support@shrublab.xyz`.

The policy commits to no use of Google user data for model training, but does not
guarantee zero data retention. The operator approved provider retention under the
applicable terms instead of the earlier ZDR-only posture. Command Code's
`typesafe/jev-1.14.0` decision model, reached through Bifrost, processes classification
content; other AI tasks and failed decisions use Bifrost's Inbox Zero route to DeepSeek
through Merge Gateway. The operator has configured ZDR restrictions for that Merge
route, but the policy does not extend that guarantee to the decision path. Provider
retention is separate from application and backup retention.

The policy is not technical enforcement. The operator must verify no-training
agreements and controls across the complete route, including fallbacks, and obtain
user consent for the disclosed processing. Configure an applicable console
policy/agreement before enabling live processing; do not assume that a model
catalogue badge or setting its ID enables a filter. Google also limits
human access and unrelated uses: removing ZDR is not permission for unrestricted
provider logging or review.

Use the public URL in the Google consent screen. Google's requirements for
[privacy disclosures](https://support.google.com/cloud/answer/13464321) and
[Workspace data use](https://developers.google.com/workspace/workspace-api-user-data-developer-policy)
apply independently of any personal-use verification exemption.
