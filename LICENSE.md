# iResolved Source Available License v0.1

**Copyright © iResolved, LLC 2026–Present. All Rights Reserved.**

**Not OSI Open Source.** This is a source-available license. It is not an Open Source
Initiative–approved license. Each version of the Software will become available under
an Open Source license on its Change Date (see §7).

**Legal hub (CLA, EULA, Terms, Privacy):** https://docs.solved.gg/legal/2026-07-04/faq  
**Commercial licensing:** intake@solved.gg

---

## Dual-class licensing model

iResolved products are offered under a **dual-class** model:

| Class | Who it is for | Governing instrument |
| --- | --- | --- |
| **Class A — Source Available** | Anyone who obtains the Software source or unofficial builds from public repositories or other channels | **This License** (`LICENSE.md`) |
| **Class B — Authenticated / commercial** | Users with an active Authenticated Account who run **official** builds obtained from Licensor’s designated distributor | [EULA](https://docs.solved.gg/legal/2026-07-04/eula), [Terms of Service](https://docs.solved.gg/legal/2026-07-04/terms), and [Privacy Policy](https://docs.solved.gg/legal/2026-07-04/privacy) |

Contributions to Licensor projects require acceptance of the
[Contributor License Agreement (CLA)](https://docs.solved.gg/legal/2026-07-04/cla).

### Special provision — Official application users (precedence)

If You have an **active account on solved.gg** (or another Authenticated Account
designated by Licensor) **and** You are logged into a version of the application that is
**officially signed and downloaded from Licensor’s designated distributor**
(currently **https://get.solved.gg** or a successor URL Licensor publishes), then You are
subject to the EULA, the iResolved Terms of Service, and the Privacy Policy.

In the event of any conflict between this License and the EULA, Terms of Service, or
Privacy Policy for such authenticated official use, the **EULA, Terms of Service, and
Privacy Policy control and take precedence** over this document.

For Authenticated Accounts in good standing under Class B, **payment and commercial-license-fee
portions** of this License may be superseded by the EULA’s commercial terms (see §2.3).
**Competition, AI, distribution, integrity, audit, and other non-payment restrictions** in
this License continue to apply unless the EULA **expressly** grants broader rights.

---

### 1. Definitions

- **“Licensor”** means iResolved, LLC and any copyright holder(s) offering the Software under this License.
- **“You” / “Licensee”** means any individual or legal entity exercising permissions granted by this License.
- **“Software”** means the source code, object code, documentation, specifications, build scripts, configuration, and any other materials made available by Licensor under this License; “Software” does not include any Workspace.
- **“Workspace”** means any directory, project, repository, database, configuration set, or collection of files and data that You create, populate, edit, or manage by running a production binary of the Software. “Workspace” includes all user-supplied or user-created content, code, documents, assets, and data inside it. “Workspace” does not include the Software, its source code, object code, Licensor-provided documentation, or any other materials made available by Licensor.
- **“Source Available”** means the Software’s source is viewable and usable only under the conditions of this License.
- **“Use”** means to access, view, run, execute, install, compile, reproduce, modify, adapt, translate, create derivative works of, distribute, convey, make available, host, provide as a service, benchmark, test, or otherwise exploit the Software, in whole or in part.
- **“Derivative Work”** has the meaning under applicable copyright law, and includes any work based on or incorporating any portion of the Software.
- **“Confidential Information”** means any non-public information included in or derivable from the Software, including architecture, roadmaps, designs, comments, test data, build pipelines, and non-public APIs, to the extent not publicly disclosed by Licensor.
- **“Competitive Offering”** means any product or service (including SaaS, hosted service, on-prem software, embedded software, library, SDK, model, agent, or API) that provides materially the same primary functionality as the Software (or any material portion of it), as reasonably understood by a person skilled in the art, including where it is the same as, substantially similar to, or functionally competitive with the Software or any material portion of it, or can reasonably substitute for the Software in the marketplace, or is intended to be used for the same or substantially similar primary purpose as the Software. For the avoidance of doubt, a product is a Competitive Offering if it is marketed or positioned as an alternative to the Software or performs the same core workflows that the Software was designed to handle.
- **“Functionally Equivalent”** means implementing materially the same features, behaviors, workflows, interfaces, data models, protocols, endpoints, schemas, command sets, or operational semantics, whether or not the code is textually similar.
- **“Artificial Intelligence System” / “AI System”** means any machine learning system, neural network, language model, multimodal model, embedding model, code assistant, agentic system, classifier, or similar system, whether provided by You or a third party.
- **“Training”** means training, pre-training, fine-tuning, continued training, reinforcement learning, distillation, supervised learning, unsupervised learning, self-supervised learning, retrieval-augmentation indexing, embedding generation, dataset construction, or any process that uses the Software (or any portion of it) as input to improve, parameterize, evaluate, or influence an AI System.
- **“AI Consumption”** means any ingestion, parsing, indexing, embedding, vectorization, annotation, labeling, tokenization, transformation, or processing of the Software by or for an AI System, including for Training.
- **“Prohibited AI Use”** means any AI Consumption of the Software except as expressly permitted under Section 4, or any use that results in the Software or its Confidential Information being incorporated, in whole or in part, into the parameters, weights, embeddings, or reasoning patterns of any AI System.
- **“Change Date”** means four (4) years after the date on which Licensor first makes **this version** of the Software available under this License.
- **“Authenticated Account”** means an account successfully authenticated by Licensor’s (or a designated affiliate’s) identity systems and in good standing, as further described in the EULA.
- **“Commercial License”** means a separate written license from Licensor granting rights beyond those in this License (including Class B arrangements under the EULA and paid enterprise agreements).

### 2. Grant of rights (limited)

Subject to Your continuous compliance with this License, Licensor grants You a limited, non-exclusive, non-transferable, non-sublicensable license to:

- view and internally evaluate the Software;
- run the Software for internal purposes; and
- modify the Software for internal purposes,

**provided** that academic or security research Use that is non-commercial and not for a Competitive Offering is permitted, so long as You do not publish or distribute any Software, Derivative Works, benchmarks, or other materials that enable a Competitive Offering or Functionally Equivalent software, and You comply with Sections 3–6.

**in each case** only as permitted by this License and only if such Use does not fall within Restricted Uses in Section 3 or Prohibited AI Use in Section 4.

#### 2.1 Personal, Small Entity, and Growth Grace Period

Notwithstanding any other provision, natural persons (individuals) and small entities (≤10 employees or <$2M USD annual revenue) may use, modify, and run the Software for personal, educational, or internal business purposes, including limited production use, provided they do not create or operate a Competitive Offering and comply with Sections 3, 4, and 6. This includes personal projects, self-hosted instances, and non-public tools.

If a small entity grows beyond the thresholds above, it shall have a grace period of one hundred eighty (180) days from the date it first exceeds either threshold to either (a) obtain a Commercial License from Licensor or (b) cease any Use that would otherwise violate this License. Licensor will not pursue enforcement actions against such entities solely for crossing the threshold during this grace period, provided they act in good faith.

#### 2.2 Workspaces

This License governs the Software only. It does not apply to any Workspace.

Use of a production binary of the Software to manage a Workspace does not subject the Workspace or its contents to this License. The Workspace and all content within it remain outside the scope of every grant, restriction, and obligation herein.

Without limiting the foregoing:

- Sections 3, 4, and 6 do not apply to the Workspace or its contents merely because a production binary was used to manage them.
- Operating or managing a Workspace with a production binary does not constitute a Competitive Offering, Functionally Equivalent software, or Prohibited AI Use under this License.
- You retain unrestricted rights to use, modify, distribute, commercialize, or otherwise exploit the Workspace and its contents.

The source code and other elements of the Software remain fully governed by this License. The carve-out applies solely to the production binary’s function as a tool for independent Workspaces.

#### 2.3 Authenticated Account and commercial terms (Class B interaction)

If You Use the Software under Class B (active Authenticated Account + official signed build from Licensor’s designated distributor), then:

1. The EULA’s commercial terms govern fees, seats, support tiers, and account access for that Use.
2. Any obligation under this License to purchase a separate Commercial License solely for **permitted non-competitive production Use** of that official build is **superseded** while Your Authenticated Account remains in good standing and Your Use stays within the EULA and Order limits.
3. Sections 3, 4, 5, 5.1, and 6 of this License (competition, AI, compliance, logging integrity, and distribution restrictions) **continue to apply** unless the EULA expressly grants broader rights in writing.
4. If Your Authenticated Account ends, is suspended, or You Use non-official builds or source outside Class B, this License applies in full to that Use, including any Commercial License requirements that are no longer superseded.

Nothing in this §2.3 grants rights to create Competitive Offerings, perform Prohibited AI Use, or redistribute the Software beyond what this License or the EULA expressly allows.

### 3. Restricted uses (competition, functional equivalents)

Unless Licensor grants You a separate Commercial License, You must **not**, and must not permit any third party to:

1. **Develop or enable a Competitive Offering.** Use the Software to develop, improve, train, operate, or provide any Competitive Offering.
2. **Create Functionally Equivalent software.** Use the Software (including exposure to its source, architecture, interfaces, or behavior) to build, design, implement, or validate Functionally Equivalent software.
3. **Benchmarking and competitive analysis publication.** You may not publish benchmarks, comparisons, evaluations, or performance results of the Software without Licensor’s prior written consent.

The restrictions in this Section apply only to Uses of the Software. They do not apply to any Workspace managed by a production binary of the Software.

**Note:** Independent development of similar functionality (including good-faith clean-room implementations) that does not rely on the Software, knowledge directly derived from it, or Prohibited AI Use is not prohibited by this License.

**Examples (non-exhaustive)** of prohibited conduct:

- Reading the codebase, then implementing a “new” library/API that matches the same endpoints, schemas, or behaviors using the Software as reference.
- Using the Software as reference to recreate identical workflows, UI flows, or system behavior, even with different naming.
- Using the Software to generate, index, or distill interfaces for competing code-generation agents, RAG systems, autonomous tooling, or similar AI Systems.
- Extracting or replicating scheduling policies, capability or permission models, secure-boot flows, IPC mechanisms, driver interfaces, or system-call semantics into any Competitive Offering or Functionally Equivalent software.

### 4. AI / ML restrictions

Unless Licensor grants You a separate Commercial License, You must **not** perform Prohibited AI Use.

#### 4.1 Prohibited AI Use includes (non-exhaustive)

- Training any AI System on the Software.
- Fine-tuning or continued training using the Software.
- Creating embeddings, vector databases, or retrieval indexes from the Software where the purpose overlaps with creating a Competitive Offering.
- Using the Software to create synthetic training data, labels, annotations, or instruction-tuning datasets for a Competitive Offering.
- Distilling, extracting, or learning behaviors, patterns, interfaces, or implementation details from the Software into an AI System whose primary purpose overlaps with the Software or any Competitive Offering.
- Using any output, summary, or derivative generated by an AI System that consumed the Software in a manner that would itself be prohibited.

The restrictions in this Section apply only to Uses of the Software. They do not apply to any Workspace managed by a production binary of the Software.

#### 4.2 Limited permitted AI assistance (narrow)

You may use an AI System **only** for ephemeral assistance (for example, autocomplete on code You authored) **if**:

- no portion of the Software is provided to the AI System beyond snippets strictly necessary for the immediate task;
- the AI provider is contractually prohibited from Training on, retaining, or using those inputs for model improvement (for example, a zero-retention / no-training enterprise tier); and
- You maintain records sufficient to demonstrate compliance.

If You cannot satisfy all conditions above, the AI use is Prohibited AI Use.

### 5. Compliance, controls, and audit support

To provide enforceable compliance hooks, You agree to:

- **Records.** Maintain complete and accurate records reasonably sufficient to demonstrate compliance with Sections 3 and 4, including (as applicable) AI tool/vendor names, settings, retention/training toggles, dates of use, and an inventory of any code or documentation provided to AI Systems.
- **Certification.** Upon Licensor’s written request (limited to once per calendar year), provide a written certification of compliance signed by an authorized representative (or by the individual for natural persons).
- **Incident notice.** Promptly notify Licensor upon discovery of any actual or suspected breach relating to Competitive Offerings, Functionally Equivalent software, or AI Consumption.
- **Audit (limited).** If Licensor has a reasonable basis to suspect material non-compliance, You will cooperate with a limited compliance review by an independent auditor under NDA, limited to verifying compliance with Sections 3–5 and focused only on records reasonably suspected of containing Software-derived material. Licensor may exercise this right through counsel or retained experts. Licensee shall bear its own costs unless the audit reveals no material breach, in which case Licensor reimburses reasonable audit costs charged by the independent auditor.

#### 5.1 Logging and tampering

Where the Software implements local, on-device compliance or integrity logging of usage, access, modifications, or AI-related interactions, those logs exist solely for compliance verification. Such logs are not transmitted to Licensor except for minimal tamper-detection or authentication events that Licensor may configure (for example, alerts that logging has been disabled, circumvented, or deleted). Licensor does not collect, store, or access substantive Workspace contents, private source code, or other private information from Licensee’s systems solely by virtue of this Section.

You must not disable, circumvent, delete, or cause the deletion of such compliance or integrity logs **where the Software provides them**, except as expressly documented by Licensor for normal product operation. Any attempt to do so, or failure to preserve such logs upon reasonable written request after a preservation notice, constitutes a material breach. Licensee agrees that willful destruction or alteration of such logs may create a rebuttable presumption of violation of Sections 3 and 4 in any dispute where those logs would have been material.

**Preservation obligation.** Upon receipt of a preservation notice from Licensor, Licensee must promptly preserve all relevant records, logs, models, and systems within Licensee’s control for the duration of any bona fide dispute, consistent with applicable law.

### 6. Distribution and external use

Unless Licensor grants You a separate Commercial License, You must not distribute, convey, sublicense, sell, or make the Software available to any third party as a product or service, including by:

- providing the Software as a hosted service;
- offering access to the Software via an API as a service to third parties;
- distributing binaries built from the Software for third-party production use; or
- incorporating any portion of the Software into any model, dataset, corpus, weights, embedding store, or similar artifact that is distributed or made available under terms more permissive than this License.

**Source and evaluation copies.** You may share unmodified copies of the Software **solely for non-production evaluation or contribution** (for example, forking a public repository to open a pull request), provided that:

1. You include this License and all copyright and proprietary notices;
2. You do not remove or obscure Licensor notices;
3. You do not relicense the Software under different terms; and
4. the share is not a Competitive Offering and does not violate Sections 3 or 4.

Licensor’s own publication of the Software (including official public repositories and the designated distributor) is not a Licensee act and does not excuse Licensee non-compliance.

### 7. Delayed relicensing (Change License)

The Change Date for **this version** of the Software is exactly four (4) years after the date on which Licensor first makes this version available under this License. On and after the Change Date, the license for **that version** automatically converts to the **GNU Affero General Public License, version 3 (AGPL-3.0-only)** as published by the Free Software Foundation at https://www.gnu.org/licenses/agpl-3.0.html.

Newer versions of the Software may be published under this License (or a successor) with their own Change Dates. Availability of a later version under AGPL-3.0-only does not relicense earlier versions before their own Change Dates.

Nothing in this Section prevents Licensor from also offering any version under additional or different licenses (including Commercial Licenses).

### 8. Intellectual property; patents; no implied rights

- **No trademark rights.** This License does not grant rights to use Licensor’s trademarks, logos, or branding, except as necessary to identify the origin of the Software and to reproduce required notices.
- **Limited patent license.** To the extent Your Use for a purpose permitted by this License would necessarily infringe patents licensable by Licensor that cover the Software, the grant in Section 2 includes a limited, non-exclusive, royalty-free patent license under those claims solely for such permitted Use. If You institute patent litigation against Licensor or any recipient alleging that the Software infringes a patent (including a cross-claim or counterclaim), any patent licenses granted to You under this License terminate as of the date such litigation is filed.
- **No broader patent grant.** Except as stated in this Section 8, no patent rights are granted.
- **Reservation of rights.** All rights not expressly granted are reserved by Licensor.

### 9. Termination and remedies

- **Automatic termination.** Any breach of Sections 3, 4, or 5.1 immediately terminates Your rights under this License. For other breaches, Licensor may terminate on 30 days’ written notice unless cured.
- **Injunctive relief.** You agree that breaches involving Competitive Offerings or Prohibited AI Use may cause Licensor irreparable harm for which monetary damages are insufficient, and You consent to injunctive and equitable relief without bond or security to the extent permitted by applicable law and the competent court.
- **Cure.** Licensor may, at its sole discretion, provide a cure period in writing.
- **Survival.** Sections 1, 5 (for outstanding obligations), 8–14, and any provisions that by nature should survive, survive termination.

### 10. Disclaimer of warranty

THE SOFTWARE IS PROVIDED “AS IS” AND “AS AVAILABLE”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT. PRE-RELEASE AND DEVELOPMENT BUILDS MAY BE INCOMPLETE OR CHANGE WITHOUT NOTICE.

### 11. Limitation of liability

TO THE MAXIMUM EXTENT PERMITTED BY LAW, IN NO EVENT WILL LICENSOR BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, REVENUE, DATA, OR GOODWILL, ARISING OUT OF OR RELATED TO THIS LICENSE OR THE SOFTWARE.

TO THE MAXIMUM EXTENT PERMITTED BY LAW, LICENSOR’S AGGREGATE LIABILITY ARISING OUT OF OR RELATED TO THIS LICENSE OR THE SOFTWARE WILL NOT EXCEED THE GREATER OF (A) THE AMOUNTS YOU PAID TO LICENSOR FOR THE SOFTWARE OR COMMERCIAL LICENSE GIVING RISE TO THE CLAIM IN THE TWELVE (12) MONTHS BEFORE THE CLAIM, OR (B) ONE HUNDRED U.S. DOLLARS (US $100).

### 12. Governing law; venue

This License and any dispute arising out of or related to it (including any non-contractual disputes or claims) will be governed by the laws of the State of Delaware, U.S.A., without regard to its conflict of law principles.

**Exclusive venue.** Subject to the Chancery carve-out below, the parties agree that any action, suit, or proceeding arising out of or related to this License or the Software will be brought exclusively in the United States District Court for the District of Delaware, and each party irrevocably submits to the personal jurisdiction and venue of such court.

**Court of Chancery carve-out.** To the extent a claim is within the subject matter jurisdiction of the Delaware Court of Chancery (including claims seeking equitable relief), Licensor may, at its option, bring such claim exclusively in the Delaware Court of Chancery (or, if that court lacks jurisdiction, in the Delaware Superior Court), and You irrevocably submit to the personal jurisdiction and venue of such court.

You waive any objection to such courts based on forum non conveniens or any similar doctrine.

### 13. No waiver; cumulative remedies; severability

Failure by Licensor to enforce any provision of this License does not constitute a waiver of its rights. All remedies provided herein are cumulative and in addition to any other remedies available at law or in equity.

If any provision of this License is held unenforceable, it will be modified to the minimum extent necessary to make it enforceable, or if modification is not possible, severed. The remaining provisions continue in full force.

### 14. Third-party components; notices; entire agreement; contact

- **Third-party components.** The Software may include third-party components under separate licenses. Those licenses govern those components alone. Nothing in this License limits rights You may have under mandatory open-source terms for those components alone.
- **Notices.** You must retain all copyright, license, and attribution notices in the Software and any permitted copies.
- **Entire agreement (Class A).** This License constitutes the entire agreement between You and Licensor regarding Class A Use of the Software and supersedes prior or contemporaneous agreements on that subject, except that Class B Use is also governed by the EULA, Terms, Privacy Policy, and any Order.
- **Contributions.** External contributions require the CLA: https://docs.solved.gg/legal/2026-07-04/cla
- **Contact.** Licensing, CLA, and commercial questions: intake@solved.gg

---

**See also:** [EULA](https://docs.solved.gg/legal/2026-07-04/eula) · [CLA](https://docs.solved.gg/legal/2026-07-04/cla) · [Terms](https://docs.solved.gg/legal/2026-07-04/terms) · [Privacy](https://docs.solved.gg/legal/2026-07-04/privacy) · [Legal FAQ](https://docs.solved.gg/legal/2026-07-04/faq)
