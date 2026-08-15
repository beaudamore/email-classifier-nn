# Production Implementation Options and Selection Criteria

## Purpose

This document defines how the trained phishing classifier can be connected to Microsoft Outlook and Exchange in production. It separates Microsoft-provided integration points from the custom services required to run the XGBoost or PyTorch model.

The classifier does not run inside Outlook or Exchange Online. It runs in a separately operated inference service. Microsoft Graph, Outlook add-ins, Exchange mail-flow rules, or an external mail gateway provide the surrounding integration.

## Shared Production Components

Every implementation option requires the following components:

1. **Shared feature library** -- one versioned implementation of the twelve Phase 1 features, used by both training and inference.
2. **Inference service** -- loads the selected model, scaler when required, calibrator, threshold, feature order, and run manifest.
3. **Policy layer** -- converts a calibrated probability into an operational action. Policy must remain separate from model inference.
4. **Decision log** -- records message identifier, model version, feature version, probability, threshold, decision, latency, and action.
5. **Feedback path** -- captures analyst and user dispositions for evaluation and later retraining.
6. **Monitoring** -- measures throughput, latency, failures, queue depth, class rates, score drift, false positives, and model-version adoption.

The inference result should use a stable contract such as:

```json
{
  "message_id": "provider-message-id",
  "classification": "phishing",
  "phishing_probability": 0.982,
  "threshold": 0.73,
  "model": "xgboost",
  "model_run": "phase2-a1e06b36c0af0662",
  "feature_version": "phase1-a1e06b36c0af0662"
}
```

## Option 1: Microsoft Graph Post-Delivery Monitoring

### Architecture

```text
Exchange Online
    -> Microsoft Graph change notification
    -> HTTPS webhook
    -> durable queue
    -> message retrieval worker
    -> shared feature library
    -> classifier service
    -> decision store
    -> alert or mailbox-action worker
```

### Microsoft-Provided Hooks

Microsoft Graph supports change-notification subscriptions for Outlook message resources. Subscriptions can use delegated or application permissions. Application permissions are required for centralized access across mailboxes rather than only the signed-in user's mailbox.

A notification without resource data identifies the changed message; the worker then retrieves the current message through Graph. Notifications with resource data require certificate-based encrypted payload handling and have restrictions on selectable properties.

The webhook must be publicly reachable over HTTPS. Microsoft documents a three-second response expectation for normal delivery. The endpoint should validate and durably queue the notification, then return `202 Accepted` instead of running inference synchronously. Subscriptions expire and require renewal and lifecycle handling.

### Custom Work Required

- Microsoft identity application registration and tenant approval.
- Least-privilege mailbox scope and secret or certificate management.
- Subscription creation, renewal, lifecycle recovery, and reconciliation.
- Webhook validation, `clientState` validation, idempotency, and replay handling.
- Durable queue, dead-letter handling, and retry policy.
- Message retrieval and normalization.
- Inference, policy evaluation, logging, and optional mailbox actions.

### Advantages

- Uses a supported Microsoft API.
- Does not change the tenant's inbound mail route.
- Supports a low-risk observation-only rollout.
- Can support user and analyst feedback without coupling mail delivery to model uptime.

### Limitations

- Analysis is post-delivery; a message may already be visible in the mailbox.
- Tenant-wide coverage requires careful permission governance and subscription operations.
- Graph throttling, notification loss, expiration, and eventual retrieval must be handled.
- Encrypted or protected message content may not be available for feature extraction.

### Best Fit

Recommended first production implementation for Exchange Online when rapid pre-delivery blocking is not mandatory.

## Option 2: Outlook Integrated Spam-Reporting Add-In

### Architecture

```text
User selects Report in Outlook
    -> SpamReporting event
    -> add-in obtains the message as EML
    -> internal reporting endpoint
    -> classifier and analyst workflow
    -> feedback store
```

### Microsoft-Provided Hooks

Outlook supports integrated spam-reporting add-ins on supported desktop and web clients. The add-in can obtain a Base64-encoded EML representation through `getAsFileAsync`, collect the user's reporting reason, forward the report to an internal system, and optionally move the reported message after processing.

### Custom Work Required

- Outlook add-in manifest and JavaScript event handler.
- Hosted add-in assets and internal reporting endpoint.
- Authentication, upload validation, EML parsing, and storage controls.
- Classifier invocation and analyst review workflow.
- Mapping user dispositions into governed model feedback data.

### Advantages

- Provides a visible, supported user-reporting workflow.
- Supplies high-value feedback and false-negative examples.
- Can send the original EML rather than only selected message properties.
- Complements either post-delivery or pre-delivery automated scanning.

### Limitations

- User initiated; it does not scan every incoming message automatically.
- Client support differs by Outlook platform and version.
- Reported messages are untrusted input and require strict parsing and retention controls.
- User reports are noisy labels and must not enter training without review and deduplication.

### Best Fit

Recommended as a feedback channel, not as the primary automated detector.

## Option 3: Outlook On-Send or Smart Alerts Add-In

### Architecture

```text
User composes outgoing message
    -> Outlook send event
    -> add-in calls policy or classifier service
    -> allow, warn, soft-block, or block send
```

### Role

Microsoft's current Outlook guidance favors Smart Alerts for modern outgoing-message checks. The older on-send feature exists for clients that do not support Smart Alerts.

### Advantages

- Can warn or block users before an outgoing message is sent.
- Useful for compromised-account behavior, sensitive-content controls, or suspicious outbound links.

### Limitations

- It applies to outgoing compose events, not automatic inbound phishing detection.
- Client, mailbox, offline, delegation, and policy behavior must be tested.
- Mail sending can depend on add-in and backend availability depending on configured mode.

### Best Fit

A separate outbound-security use case. It is not the primary deployment path for this inbound classifier.

## Option 4: Exchange Online Mail-Flow Rules

### Role

Exchange Online mail-flow rules evaluate messages in transit using Microsoft-defined conditions, exceptions, and actions. They can reject, redirect, delete, annotate, or otherwise process matching messages, and they support audit and test modes.

### Advantages

- Executes during mail transport.
- Centrally administered.
- Supports test modes before enforcement.
- Appropriate for deterministic policy based on headers, sender properties, text matches, or classifications already present in the message.

### Limitations

- Mail-flow rules do not provide a general hook for executing this Python XGBoost or PyTorch model.
- Rule predicates cannot reproduce the complete model decision boundary.
- Encrypted content can restrict inspection.
- Rule changes can have tenant-wide consequences.

### Best Fit

Use as a policy enforcement companion when a trusted upstream component has already stamped a header or classification that a rule can consume. Do not attempt to translate the trained model into transport rules.

## Option 5: Pre-Delivery Mail-Security Gateway

### Architecture

```text
Internet
    -> custom or third-party SMTP security gateway
    -> MIME parsing and feature extraction
    -> classifier service
    -> allow, quarantine, reject, or tag
    -> Exchange Online
```

### Custom Work Required

- Supported mail-routing and connector design for the target Exchange environment.
- Highly available SMTP or security-gateway infrastructure.
- MIME parsing, queueing, retry, back-pressure, and delivery-status handling.
- Fail-open or fail-closed policy with documented outage behavior.
- Certificate, DNS, routing, anti-loop, and disaster-recovery controls.
- Model inference that meets the mail-flow latency budget.

### Advantages

- Can classify and act before delivery to the mailbox.
- Provides centralized coverage independent of Outlook clients.
- Can retain the full transport message and headers for analysis.

### Limitations

- Highest operational and security risk.
- Mail delivery becomes dependent on gateway availability and correctness.
- Incorrect routing or policy can delay, duplicate, reject, or lose legitimate mail.
- Requires substantially more testing, observability, and operational ownership.

### Best Fit

Use only when pre-delivery enforcement is mandatory and the organization can operate a highly available mail-security service.

## Option 6: On-Premises Exchange Transport Integration

On-premises Exchange has server-side transport extensibility that differs from Exchange Online. Any transport-agent design must be matched to the exact supported Exchange Server edition, version, deployment topology, and Microsoft support policy before implementation.

This option must not be assumed to work in Exchange Online. It requires a separate design review for the actual on-premises environment.

## Decision Matrix

| Criterion | Graph monitoring | Spam add-in | On-send / Smart Alerts | Mail-flow rules | SMTP gateway |
|---|---:|---:|---:|---:|---:|
| Automatic inbound coverage | High | Low | None | High for rule logic | High |
| Pre-delivery action | No | No | Not inbound | Yes | Yes |
| Runs custom ML model directly | Via custom service | Via custom service | Via custom service | No | Via custom service |
| Outlook client dependency | None | Yes | Yes | None | None |
| Mail-delivery availability risk | Low | Low | Outbound only | Medium | High |
| Implementation complexity | Medium | Medium | Medium | Low | Very high |
| Feedback collection value | Medium | High | Low for inbound | Low | Medium |
| Recommended initial role | Primary pilot | Feedback | Separate outbound use | Companion policy | Later enforcement |

## Selection Criteria

Choose the implementation using explicit requirements rather than model speed alone.

### 1. Enforcement Timing

- Choose **Graph monitoring** when detection shortly after delivery is acceptable.
- Choose a **gateway** when the message must be evaluated before mailbox delivery.
- Choose **mail-flow rules** only when deterministic Exchange predicates or an upstream stamped result are sufficient.

### 2. Required Coverage

Document whether the system covers:

- A pilot mailbox group or the full tenant.
- User mailboxes, shared mailboxes, and delegated folders.
- Incoming mail only or internal and outgoing mail as well.
- Desktop, web, and mobile Outlook clients.
- Encrypted and protected messages.

### 3. Permitted Actions

Define actions independently from model classification:

- Observe and log.
- Alert an analyst.
- Add a category or warning.
- Move to a review folder.
- Quarantine.
- Reject or delete.

Automatic destructive actions require a higher evidence threshold than alerts or categorization.

### 4. Reliability Requirements

The selected design must define:

- Availability target and recovery-time objective.
- Queue durability, retry, idempotency, and dead-letter behavior.
- Subscription renewal and missed-event reconciliation for Graph.
- Fail-open or fail-closed behavior for inline enforcement.
- Maximum acceptable analysis and delivery latency.
- Capacity during burst mail volume and downstream outages.

### 5. Security and Privacy

Require:

- Least-privilege access to explicitly authorized mailboxes.
- Encryption in transit and at rest.
- Managed secrets or certificates with rotation.
- Validation of Graph notification state and tokens.
- Strict MIME and HTML parsing of untrusted messages.
- Data minimization, retention limits, and auditable access.
- No fetching of URLs or attachments referenced by suspicious messages during feature extraction.

### 6. Model Governance

A production candidate must provide:

- Immutable model, calibrator, threshold, scaler, feature list, and run manifest.
- Reproducible mapping from Phase 1 fingerprint to model run.
- Validation-selected threshold with untouched test results.
- Per-version rollback capability.
- Shadow comparison before promotion.
- Drift and false-positive monitoring after deployment.
- A documented process for analyst corrections and retraining data acceptance.

### 7. Operational Acceptance Metrics

Measure on the actual production path:

- End-to-end p50, p95, and p99 analysis latency.
- Sustained and burst emails per second.
- Queue age and depth.
- Notification, retrieval, parsing, and inference failure rates.
- Phishing recall, precision, false-positive rate, and calibration.
- False positives by mailbox, sender type, source, and legitimate-email category.
- Adversarial and obfuscated phishing recall.
- Percentage of messages that cannot be fully inspected.

Performance acceptance must include retrieval, parsing, feature extraction, inference, calibration, policy, and result persistence. Model-only throughput is insufficient.

## Recommended Delivery Sequence

### Stage 1: Offline Harness

- Extract the twelve features through a shared library.
- Load the selected model artifacts outside the notebook.
- Replay held-out EML or normalized messages.
- Verify prediction parity with notebook output.

### Stage 2: Graph Shadow Pilot

- Subscribe only to approved pilot mailboxes.
- Queue and analyze messages without modifying mailboxes.
- Record scores and compare them with analyst dispositions.
- Reconcile notifications against mailbox state.

### Stage 3: Analyst Alerts and User Feedback

- Alert analysts above a conservative threshold.
- Add the integrated Outlook spam-reporting add-in.
- Store reviewed outcomes separately from raw user reports.

### Stage 4: Reversible Mailbox Actions

- Add a category or move high-confidence messages to a review folder.
- Preserve an audit trail and straightforward restoration path.
- Continue measuring false positives before stronger enforcement.

### Stage 5: Pre-Delivery Decision

Proceed to an SMTP gateway only if post-delivery response cannot meet the documented security requirement. Complete a separate availability, routing, disaster-recovery, and mail-integrity review before changing production mail flow.

## Initial Recommendation

Use **Microsoft Graph post-delivery monitoring** as the first automated implementation and an **integrated spam-reporting add-in** as the feedback mechanism. Keep the pilot observation-only until real production traffic confirms model quality, feature parity, permissions, reliability, and latency.

Treat a pre-delivery gateway as a later architecture decision, not as the initial model deployment.

## Verified Microsoft References

The following Microsoft documentation was checked on 2026-08-14:

- [Change notifications for Outlook resources in Microsoft Graph](https://learn.microsoft.com/en-us/graph/outlook-change-notifications-overview)
- [Receive Microsoft Graph change notifications through webhooks](https://learn.microsoft.com/en-us/graph/change-notifications-delivery-webhooks)
- [Implement an integrated spam-reporting Outlook add-in](https://learn.microsoft.com/en-us/office/dev/add-ins/outlook/spam-reporting)
- [On-send feature for Outlook add-ins](https://learn.microsoft.com/en-us/office/dev/add-ins/outlook/outlook-on-send-addins)
- [Mail-flow rules in Exchange Online](https://learn.microsoft.com/en-us/exchange/security-and-compliance/mail-flow-rules/mail-flow-rules)
