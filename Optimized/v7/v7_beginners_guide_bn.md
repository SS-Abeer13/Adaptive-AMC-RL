---
title: "একটি শিক্ষানবিস গাইড: RL-ভিত্তিক Link Adaptation — শুরু থেকে শেষ পর্যন্ত"
---

# একটি শিক্ষানবিস গাইড: RL-ভিত্তিক Link Adaptation, একদম গোড়া থেকে

**এই গাইডটি কাদের জন্য:** যাঁরা theory-তে (optimization, control, probability, এবং কিছুটা machine learning) স্বচ্ছন্দ, কিন্তু cellular network বা wireless communication নিয়ে বিশেষ কোনো পূর্ব-জ্ঞান নেই — তাঁদের জন্য এই গাইড লেখা। প্রতিটি domain-specific concept ব্যবহারের আগে একদম গোড়া থেকে বোঝানো হয়েছে; শুধু mathematical maturity ধরে নেওয়া হয়েছে, আর কিছু নয়।

**এতে কী আছে:** পুরো research program-এর গল্প — "আমরা আসলে কোন সমস্যাটা সমাধান করছিলাম" থেকে শুরু করে ছয়টি বড় redesign (v1 থেকে v6) পেরিয়ে সবচেয়ে rigorous শেষ version (v7) পর্যন্ত। শেষে দেখানো হয়েছে, কেন চূড়ান্ত উত্তরটি একটি সাবধানে অর্জিত null result হয়ে দাঁড়ালো, এবং কেন সেটিও একটি প্রকৃত scientific contribution।

**Technical term নিয়ে একটি কথা:** যাবতীয় domain-specific technical term (যেমন MCS, CQI, SINR, BLER, OLLA, HARQ, RL, TTI ইত্যাদি) ইচ্ছাকৃতভাবে **ইংরেজিতেই** রাখা হয়েছে — কারণ এগুলো আন্তর্জাতিক মানের terminology, বাংলায় অনুবাদ করলে অর্থের নির্ভুলতা নষ্ট হওয়ার ঝুঁকি থাকে। বাকি সব ব্যাখ্যা, যুক্তি এবং আলোচনা বাংলায় লেখা।

---

## রোডম্যাপ

1. **আসল সমস্যাটা কী** — cellular downlink আসলে কী জিনিস, এবং কীভাবে transmit করতে হবে তা বেছে নেওয়া কেন এত কঠিন।
2. **প্রচলিত সমাধান** — OLLA-কে একটি control loop হিসেবে ব্যাখ্যা।
3. **কেন reinforcement learning এখানে আসে** — decision-process formalism থেকে গড়ে তোলা।
4. **একটি ভরসাযোগ্য pipeline তৈরির দীর্ঘ পথ (v1–v5)** — চারটি debugging round, প্রতিটি একটি নির্দিষ্ট সাংখ্যিক red flag দিয়ে শুরু হয়েছে।
5. **v6 থেকে পাওয়া অস্বস্তিকর শিক্ষা** — কীভাবে "RL আসলেই কাজ করছে" এই দাবিটা একটা illusion হতে পারে, আর কীভাবে সেই illusion ধরা পড়ল।
6. **পুনর্গঠিত experiment (v7)** — পাঁচটি নির্দিষ্ট পরিবর্তন, প্রতিটি v6-এর একটি ফাঁক বন্ধ করে।
7. **experiment-টাকে কীভাবে rigorous করা হলো** — pre-registration আর hypothesis testing, গোড়া থেকে ব্যাখ্যা করা।
8. **experiment চালানোর পর কী হলো** — headline result।
9. **গোয়েন্দাগিরি** — কেন result এমন এলো, তা diagnose করা।
10. **ধাপে ধাপে সেটা ঠিক করা।**
11. **একটি adversarial sanity check, আর চূড়ান্ত decisive experiment।**
12. **বড় ছবি: এর প্রকৃত অর্থ কী।**
13. **Glossary**, পড়ার সময় হাতের কাছে রাখার জন্য।

---

## Part 1: আসল সমস্যাটা কী

### 1.1 Cellular Downlink আসলে কী

একটি cellular base station (একটি cell tower) একই সঙ্গে অনেক user-কে সেবা দেয়। প্রতিটি user-এর হাতে একটি phone; base station-এর হাতে radio spectrum-এর একটি নির্দিষ্ট পরিমাণ (frequency bandwidth), যা সে ব্যবহার করতে পারে। **Downlink** মানে নির্দিষ্টভাবে base station থেকে user-এর দিকে যাওয়া transmission — base station পাঠাচ্ছে, user-এর phone গ্রহণ করছে।

সময়কে ছোট ছোট টুকরোয় ভাগ করা হয়, যাকে বলা হয় **Transmission Time Interval (TTI)** — এই project-এ প্রতিটি এক millisecond দীর্ঘ। প্রতিটি TTI-তে base station একটি সিদ্ধান্ত নেয়: এই মুহূর্তে কোন user data পাঠানোর সুযোগ পাবে, আর কোন rate-এ?

### 1.2 Modulation and Coding: Rate বনাম Reliability

এখানেই মূল engineering-এর টানাপোড়েন। Radio channel দিয়ে data পাঠাতে হলে base station bit-গুলোকে radio waveform-এ encode করে — দুইটা জিনিসের মিশেলে: **modulation** (প্রতিটি transmitted symbol-এ কতগুলো bit ঢোকানো হচ্ছে) আর **coding** (error থেকে বাঁচতে কতটা redundancy যোগ করা হচ্ছে)। এই দুই সিদ্ধান্ত একসঙ্গে মিলে হয় **Modulation and Coding Scheme (MCS)**।

উঁচু একটি MCS প্রতি symbol-এ বেশি bit বহন করে আর কম redundancy রাখে — এতে গতি বাড়ে, কিন্তু সামান্য noise বা interference-এই তা corrupt হয়ে যাওয়ার সম্ভাবনাও বেড়ে যায়। নিচু একটি MCS ধীর, কিন্তু noise-এর বিরুদ্ধে অনেক বেশি সহনশীল। এটাই সেই classic information-theoretic trade-off: যেকোনো নির্দিষ্ট channel quality-র জন্য (মোটামুটিভাবে received signal power-এর সাথে noise-plus-interference power-এর অনুপাত হিসেবে মাপা হয়, যাকে বলে **SINR** — Signal-to-Interference-plus-Noise Ratio) একটি সর্বোচ্চ rate থাকে, যেখানে error probability প্রায় শূন্যে রেখেও transmit করা সম্ভব — এটাই **Shannon capacity**-র পেছনের intuition। বাস্তব system এই theoretical limit-এ পৌঁছায় না, কিন্তু একই ধরনের trade-off থেকেই যায়: প্রকৃত SINR-এর তুলনায় বেশি aggressive একটি MCS বেছে নিলে error rate তীব্রভাবে বেড়ে যায়; আবার খুব conservative একটি MCS বেছে নিলে throughput-এর অনেকটাই অব্যবহৃত থেকে যায়।

কোনো নির্দিষ্ট MCS একটি নির্দিষ্ট channel-এ আসলে কতবার fail করে, তা মাপে **Block Error Rate (BLER)** — অর্থাৎ, একটি নির্দিষ্ট MCS ও SINR-এ পাঠানো একটি data block uncorrectable error নিয়ে receive হওয়ার probability। SINR স্থির রেখে MCS বাড়ালে BLER দ্রুত বেড়ে যায় — এক ধাপ MCS বাড়ালেই error probability হঠাৎ লাফিয়ে উঠতে পারে, কারণ noise margin-টা ততক্ষণে খেয়ে ফেলা হয়েছে। প্রতিটি MCS-এর জন্য এই SINR-বনাম-BLER সম্পর্ককে অনেক সময় বলা হয় **waterfall curve**, কারণ সঠিক axes-এ আঁকলে এটা দেখতে অনেকটা একটা সরু SINR range-এর মধ্যে "সবসময় fail" থেকে "কখনো fail করে না"-তে হঠাৎ পড়ে যাওয়া জলপ্রপাতের মতো লাগে।

**মূল সিদ্ধান্তটা আরেকবার বলি:** প্রতিটি TTI-তে, প্রতিটি user-এর জন্য, সেই MCS বেছে নিতে হবে যা বর্তমান channel অবস্থা অনুযায়ী প্রত্যাশিত useful throughput-কে সর্বোচ্চ করে।

### 1.3 কেন সবসময় সবচেয়ে উঁচু MCS ব্যবহার করা যায় না

SINR যদি নিখুঁতভাবে জানা থাকত আর স্থির থাকত, তাহলে এটা একটা সমাধান হয়ে যাওয়া, static সমস্যা হতো — সেই SINR-এর জন্য সেরা MCS টেবিল থেকে দেখে নিলেই কাজ শেষ। কিন্তু এই সমস্যাটা সত্যিকারের একটা কঠিন *control* সমস্যা থেকে যায়, নিছক একটা lookup-table সমস্যা নয়, কারণ — **সিদ্ধান্ত নেওয়ার মুহূর্তে base station প্রকৃত, তাৎক্ষণিক SINR জানেই না।**

### 1.4 Channel Quality Indicator (CQI) এবং Feedback

User-এর phone channel মেপে একটা summary ফেরত পাঠায় — একে বলে **Channel Quality Indicator (CQI)**, মূলত SINR-এর একটা quantized অনুমান। এই report base station পর্যন্ত পৌঁছাতে সময় লাগে, তারপর process হতে সময় লাগে, এবং তারপরই base station সেই user-এর *পরবর্তী* transmission-এর জন্য একটা MCS বেছে নেয়। এতে দুটো সমস্যা তৈরি হয়, যেগুলো একসাথে বাড়তে থাকে:

- **Feedback delay।** সময় $t$-তে base station যে CQI report ব্যবহার করছে, তা আসলে কিছুটা আগের সময় $t - d$-তে মাপা হয়েছিল, যেখানে $d$ কয়েক millisecond-এর (মানে কয়েকটা TTI-র) একটা delay। ততক্ষণে channel বদলে গেলে, base station পুরনো তথ্যের ওপর ভিত্তি করে কাজ করছে।
- **Measurement noise।** CQI report নিজেই একটা noisy অনুমান, প্রকৃত SINR নয়।

### 1.5 আসল সমস্যাটা

সব মিলিয়ে দেখলে: base station-কে *এখনই* একটা MCS বেছে নিতে হবে, অথচ হাতে আছে শুধু একটা noisy, delayed অনুমান — এমন একটা channel-এর, যেটা সেই অনুমান নেওয়ার পর থেকে হয়তো বদলে গেছে। User স্থির থাকলে আর channel স্থিতিশীল থাকলে, কয়েক millisecond-এর delay খুব একটা গুরুত্বপূর্ণ নয়। কিন্তু user যদি চলমান কোনো vehicle-এ থাকে, তাহলে সেই delay-র মধ্যেই channel যথেষ্ট বদলে যেতে পারে — একে বলে **Doppler spread** (channel কত দ্রুত decorrelate হয়, তা নির্ভর করে user-এর speed আর carrier frequency-র ওপর), আর এটাই ঠিক করে দেয় channel-এর **coherence time** — যে সময়-window-এর মধ্যে channel-কে মোটামুটি স্থির ধরে নেওয়া যায়। Feedback delay যখন এই coherence time-কে ছাড়িয়ে যায়, তখন CQI report প্রায় অকেজো হয়ে যায় বর্তমান channel অনুমান করার জন্য — অনেকটা পাঁচ মিনিট আগের আবহাওয়া দেখে আজকের পোশাক বেছে নেওয়ার মতো।

এটাই সেই মৌলিক সমস্যা, যা **link adaptation** সমাধান করতে চায়: delayed আর noisy channel তথ্যের ওপর ভিত্তি করে, প্রতিটি TTI-তে, প্রতিটি user-এর জন্য, এমন একটা MCS বেছে নেওয়া, যাতে throughput সর্বোচ্চ হয় আর error নিয়ন্ত্রণে থাকে।

---

## Part 2: প্রচলিত সমাধান — OLLA, একটি Control Loop হিসেবে

### 2.1 থার্মোস্ট্যাটের সাথে তুলনা

Control theory পড়ে থাকলে এই অংশটা সাথে সাথেই চেনা মনে হবে। Link adaptation-এর industry-standard সমাধানের নাম **Outer Loop Link Adaptation (OLLA)**, আর এর গঠন একটা থার্মোস্ট্যাটের চেয়ে খুব একটা জটিল কিছু নয়।

একটা থার্মোস্ট্যাট ঘরের thermal dynamics নিখুঁতভাবে model করার চেষ্টা করে না। এটা করে সহজ আর মজবুত একটা কাজ: ঘর বেশি ঠান্ডা হলে heat একটু বাড়াও; বেশি গরম হলে কমাও; এভাবে চলতে থাকো। সময়ের সাথে সাথে এটা target temperature-এর কাছাকাছি স্থির হয়ে যায়, feedback loop-এর মাধ্যমেই এমন সব জিনিস correct করে ফেলে যা কখনো explicitly model করাই হয়নি — যেমন বাতাসের হালকা টান, রোদ, বা খোলা জানালা।

OLLA ঠিক এই কাজটাই করে, শুধু MCS বেছে নেওয়ার জন্য। এটা একটা running numerical **offset** $\Delta_{\text{OLLA}}$ ধরে রাখে, যা MCS-এ ম্যাপ করার আগে reported CQI-র সাথে যোগ করা হয়:

$$\text{effective SINR}_t = \text{reported SINR}_t + \Delta_{\text{OLLA}}$$

### 2.2 আপডেট নিয়ম

প্রতিটি transmission-এর পর receiver জানায় সেটা সফল হয়েছে (ACK, acknowledgment) নাকি ব্যর্থ (NACK, negative acknowledgment) — এটা দ্রুত, local feedback, ধীরগতির CQI reporting loop থেকে একেবারে আলাদা। OLLA সাথে সাথেই তার প্রতিক্রিয়া দেখায়:

$$
\Delta_{\text{OLLA}} \leftarrow
\begin{cases}
\Delta_{\text{OLLA}} + \delta_{\text{up}} & \text{ACK হলে (সফল): একটু ওপরে ঠেলো, পরের বার সামান্য বেশি aggressive হও} \\
\Delta_{\text{OLLA}} - \delta_{\text{down}} & \text{NACK হলে (ব্যর্থ): পিছিয়ে আসো, বেশি সতর্ক হও}
\end{cases}
$$

Step size $\delta_{\text{up}}$ আর $\delta_{\text{down}}$ ঠিকমতো বেছে নিলে, এই সহজ ওঠা-নামার নিয়মটাই দীর্ঘমেয়াদে প্রমাণিতভাবে একটা target error rate $P_{\text{target}}$-এ (প্রথাগতভাবে ১০%) এসে স্থির হয়। এর ভারসাম্য শর্তটা হলো:

$$(1-P_{\text{target}}) \cdot \delta_{\text{up}} = P_{\text{target}} \cdot \delta_{\text{down}}$$

সহজ কথায় বললে: success সাধারণ একটা ঘটনা (target error rate-এ, ধরুন ৯০% সময়ে ঘটে), তাই প্রতিটা success offset-কে অল্প একটু ওপরে ঠেলবে; আর failure বিরল (মাত্র ১০% সময়), তাই প্রতিটা failure offset-কে সে অনুপাতে বেশি নিচে নামাবে — অনেক transmission-এর গড়ে যাতে ভারসাম্য বজায় থাকে।

### 2.3 OLLA কী পারে, কী পারে না

Control-theory-র ভাষায়, এটা একটা সহজ **integral controller**: error signal (ACK/NACK)-এর ওপর ভিত্তি করে সময়ের সাথে সাথে একটা correction জমা করে। এর জন্য কোনো calibration লাগে না — প্রথম দিনেই deploy করে দেওয়া যায়, নির্দিষ্ট deployment সম্পর্কে কোনো আগাম জ্ঞান ছাড়াই — আর এটা প্রমাণিতভাবে স্থিতিশীল, নিজের target-এর দিকে ফিরে আসতে থাকে।

কিন্তু এর একটা structural সীমাবদ্ধতা আছে, যা যেকোনো control theorist সাথে সাথে চিনে ফেলবেন: এটা পুরোপুরি **reactive**। শুধু যা আগে ঘটেছে (একটা অতীত ACK বা NACK) তার প্রতিক্রিয়া দেখায়; channel সম্পর্কে এর কোনো model নেই, কোনো পরিবর্তন ঘটার আগেই তা অনুমান করার ক্ষমতাও নেই। Channel হঠাৎ খারাপ হতে শুরু করলে (ধরা যাক user একটা shadowed এলাকায় ঢুকে পড়ল), OLLA সেটা টের পায় failure দেখা দেওয়ার *পরেই* — ততক্ষণে সে বেশ কিছুক্ষণ ধরে খুব aggressive-ভাবে transmit করেছে, failed attempt-এ throughput নষ্ট করেছে, তারপর গিয়ে সংশোধন করেছে।

**এটাই ঠিক সেই ফাঁক, যা একটা predictive, state-aware controller নীতিগতভাবে বন্ধ করতে পারত** — আর এটাই সেই ফাঁক, যেটা reinforcement learning চেষ্টা করে দেখার motivation যোগায়।

---

## Part 3: কেন Reinforcement Learning এখানে আসে

### 3.1 একটা Decision Process আসলে কী, একদম গোড়া থেকে

Reinforcement learning (RL) হলো machine learning-এর সেই শাখা, যা sequential decision-making নিয়ে কাজ করে: একটা agent বারবার পৃথিবী সম্পর্কে কিছু observe করে, একটা action নেয়, একটা সাংখ্যিক reward পায়, আর পৃথিবী নিজে এগিয়ে যায় — এবং agent-এর লক্ষ্য হলো, অভিজ্ঞতা থেকে শিখে, action বেছে নেওয়ার এমন একটা নিয়ম (একটা **policy**) বানানো, যা দীর্ঘমেয়াদে জমে ওঠা reward-কে সর্বোচ্চ করে।

Formally এটাকে ধরা হয় একটা **Markov Decision Process (MDP)** দিয়ে: state, action, transition dynamics, আর reward function-এর একটা tuple। প্রতিটা discrete time step-এ agent থাকে কোনো একটা state $s_t$-তে, তার policy $\pi$ অনুযায়ী একটা action $a_t$ নেয়, environment কোনো (হয়তো অজানা) dynamics অনুযায়ী একটা নতুন state $s_{t+1}$-এ চলে যায়, আর agent পায় একটা reward $r_t$। Agent-এর লক্ষ্য হলো এমন একটা $\pi$ খুঁজে বের করা যা প্রত্যাশিত discounted cumulative reward, $\mathbb{E}\left[\sum_t \gamma^t r_t\right]$, সর্বোচ্চ করে — যেখানে $\gamma \in [0,1)$ ভবিষ্যতের reward-কে discount করে।

Agent যখন প্রকৃত state সরাসরি দেখতে পায় না — শুধু কিছু আংশিক, noisy signal পায়, যা state-এর সাথে সম্পর্কিত — তখন এটা সাধারণীকৃত হয় একটা **Partially Observable MDP (POMDP)**-তে। এটাই link adaptation-এর জন্য সঠিক framing: agent (মানে base station-এর link-adaptation algorithm) কখনোই প্রকৃত তাৎক্ষণিক SINR দেখতে পায় না; শুধু একটা delayed, noisy CQI report দেখে।

### 3.2 Link Adaptation-কে এই Formalism-এ বসানো

একবার POMDP-র কাঠামো হাতে পেলে, মিলটা সরাসরি বসে যায়:

- **State (observation):** reported CQI-র history, বর্তমান OLLA offset, আর system-কে যা যা আরও দেওয়া হয়েছে (নিচে আরও বিস্তারিত)।
- **Action:** পরবর্তী transmission-এর জন্য কোন MCS বেছে নেওয়া হবে।
- **Reward:** আসলে যে throughput ডেলিভার হলো — নির্ভর করে বেছে নেওয়া MCS সফল হলো নাকি ব্যর্থ, *প্রকৃত* (অদেখা) channel state অনুযায়ী।
- **Transition dynamics:** নিয়ন্ত্রিত হয় প্রকৃত পদার্থবিদ্যা দিয়ে — path loss, fading, mobility, interference — যা agent-কে explicitly জানার দরকার নেই; শুধু অভিজ্ঞতা থেকে বুঝে নিতে হয় কী কাজ করে।

### 3.3 কেন এটা স্বাভাবিকভাবেই একটা RL সমস্যার মতো দেখায়

OLLA-র সহজ reactive নিয়মের তুলনায়, link adaptation-কে RL হিসেবে দেখার আকর্ষণটা এখানে: একটা যথেষ্ট expressive policy — বিশেষত, RL দিয়ে trained একটা neural network — নীতিগতভাবে observed state-এর *pattern* দেখে সিদ্ধান্ত নিতে শিখতে পারে, যা একটা সহজ scalar integrator একেবারেই ধরতে পারে না: SINR history-র trend, user mobility-র সাথে সম্পর্ক, interference কীভাবে বদলাতে থাকে তার গঠন, ইত্যাদি। এমন pattern যদি সত্যিই থাকে আর কাজে লাগানোর মতো হয়, RL-এর সেগুলো খুঁজে বের করে ব্যবহার করতে পারার কথা — আর তাই OLLA-র মতো একটা policy-কে (যেটা structurally সেগুলো ব্যবহারই করতে পারে না) ছাড়িয়ে যাওয়ার কথা।

এটা সত্যিকারের একটা যুক্তিসঙ্গত hypothesis। এটা *সত্যি* কি না — এই নির্দিষ্ট সমস্যায়, বাস্তবসম্মত পরিস্থিতিতে — সেটাই ঠিক সেই empirical প্রশ্ন, যা এই পুরো research program খুঁজে বেড়িয়েছে। আর দেখা যাবে, সৎ উত্তরটা একটা সহজ "হ্যাঁ"-এর চেয়ে ঢের বেশি সূক্ষ্ম।

### 3.4 একটা চতুর পুনর্বিন্যাস: OLLA-Relative Action Encoding

এখানে একটু থামা দরকার, কারণ এই design choice-টা ভালো experimental hygiene-এর একটা উদাহরণ। RL agent-কে যদি সরাসরি একটা MCS বেছে নিতে বলা হয় — OLLA কী বেছে নিত তার থেকে সম্পূর্ণ স্বাধীন একটা absolute action — তাহলে সেটা একটা অন্যায্য প্রতিযোগিতা হয়ে দাঁড়ায়: OLLA-র হাতে আছে দ্রুত ACK/NACK feedback (Part 2-এ বর্ণিত outer loop), কিন্তু RL agent-এর state-এ যদি সেই একই feedback না থাকে, তাহলে তাকে এক হাত বাঁধা অবস্থায় লড়তে বলা হচ্ছে। তখন "RL হেরে গেল OLLA-র কাছে" — এমন যেকোনো result আসলে একটা তথ্যের ঘাটতিই মাপবে, প্রকৃত কোনো algorithmic দুর্বলতা নয়।

এই পুরো প্রজেক্ট জুড়ে ব্যবহৃত সমাধানের নাম **OLLA-relative action encoding**: প্রতিটা RL policy (এবং প্রতিটা comparator) নিজের মধ্যে *একই* OLLA loop বহন করে, একই ACK/NACK feedback থেকে একই reference offset $\Delta_{\text{OLLA}}$ হিসাব করে। RL agent-এর action তখন সরাসরি "কোন MCS ব্যবহার করব" নয়, বরং **OLLA নিজে যা সিদ্ধান্ত নিয়েছে তার ওপর একটা additive correction**:

$$\text{chosen CQI} = \text{OLLA-corrected reference CQI} + a_t, \qquad a_t \in \{-K, \dots, -1, 0, 1, \dots, K\}$$

লক্ষ করুন, action $a_t = 0$ বেছে নিলে RL policy *ঠিক* plain OLLA-র মতোই আচরণ করে। এর একটা সুন্দর পরিণতি আছে: এতে by construction নিশ্চিত হয়ে যায় যে RL কখনোই নীতিগতভাবে OLLA-র চেয়ে খারাপ করতে পারবে না (সবসময় শুধু 0 বেছে নিতেও শিখতে পারে), আর এতে experimental প্রশ্নটাও ঠিক সেই জায়গায় ফোকাস করে — **agent কি OLLA যা এমনিতেই করে, তার বাইরে গিয়ে কিছু শিখতে পারে?** — "agent-এর হাতে কি OLLA-র মতোই basic feedback আছে" এই প্রশ্নের সাথে গুলিয়ে না গিয়ে। এটা অনেকটা statistics আর econometrics-এর একটা পরিচিত কৌশলের মতো: একটা rich model-কে একটা naive model-এর সাথে সরাসরি তুলনা না করে, re-parameterize করা হয় যাতে naive model richer model-এর একটা বিশেষ ক্ষেত্র হয়ে যায় (এখানে, শূন্য vector), আর তারপর দেখা হয় richer model-এর *অতিরিক্ত* parameter গুলো নিজেদের যোগ্যতা প্রমাণ করতে পারে কি না।

এই নির্দিষ্ট formulation — OLLA-relative encoding — নিজেই একটা আগের debugging history-র ফসল, প্রথম চেষ্টাতেই পাওয়া কিছু না। সেই history-ই পরের অংশের বিষয়, কারণ এখান থেকেই সেই research discipline প্রতিষ্ঠিত হয়েছে, যা বাকি পুরো গল্প জুড়ে বহন করা হয়েছে: একটা বিস্ময়কর সংখ্যা — ভালো হোক বা খারাপ — তদন্ত করার মতো একটা সূত্র, at face value মেনে নেওয়ার মতো একটা result নয়।

---

## Part 4: একটা ভরসাযোগ্য Pipeline তৈরির দীর্ঘ পথ (v1–v5)

"RL কি OLLA-কে হারায়" — এই প্রশ্নটা সততার সাথে জিজ্ঞেস করার আগে, underlying simulation আর training pipeline-টাকেই তৈরি করে debug করতে হয়েছিল। একটা বিশ্বাসযোগ্য version-এ পৌঁছাতে লেগেছিল চারটা বড় iteration, প্রতিটা শুরু হয়েছিল একটা নির্দিষ্ট সাংখ্যিক red flag দিয়ে। এই history গুরুত্বপূর্ণ দুটো কারণে: এটাই সেই সাধারণ research discipline প্রতিষ্ঠা করে, যা বাকি গল্প জুড়ে চলে; আর এটা ব্যাখ্যা করে কেন v6 (v1 নয়) হলো "adaptivity-র কি সত্যিই কোনো value আছে" — এই প্রশ্নের প্রকৃত শুরুর বিন্দু, যা নিয়ে আলোচনা হয়েছে Part 5-এ।

### 4.1 v1: Absolute Per-User Action, এবং একটা Tie-Breaking Bug

সবচেয়ে প্রথম version-এ agent-রা সরাসরি ও স্বাধীনভাবে প্রতিটা user-এর জন্য একটা MCS বেছে নিত — তখনো কোনো OLLA-relative encoding ছিল না, user-দের মধ্যে কোনো shared learning-ও ছিল না।

**Red flag:** trained tabular RL সবচেয়ে সাধারণ, naive fixed-mapping baseline-এর চেয়েও অনেক নিচে performance দেখাত — একটু কম না, বরং এমন কিছু যা মনে হচ্ছিল প্রায় train-ই হয়নি।

**মূল কারণ, প্রকৃত decision logic ট্রেস করে খুঁজে পাওয়া গেল:** দুটো সমস্যা একসাথে কাজ করছিল। প্রথমত, software-এর built-in একটা function — যেটা estimated action-value-এর টেবিল থেকে সেরা action খুঁজে বের করে — default হিসেবে tie ভাঙত *প্রথম* matching index ফেরত দিয়ে। Training-এর শুরুর দিকে কোনো action-ই যথেষ্ট চেষ্টা করা হয়নি real পার্থক্য বোঝার মতো, তাই বেশিরভাগ action-value estimate তাদের একই রকম initial value-তে (সাধারণত শূন্য) আটকে থাকত, ফলে tied থাকত — আর তাই "সেরা action বেছে নাও" ধাপটা নীরবে, প্রতিবার tie হলেই, সবচেয়ে নিচু-index-এর action-এর দিকে systematically ঝুঁকে থাকত, নিরপেক্ষ বা random choice করার বদলে। এটা RL implementation-এর একটা চেনা লুকানো bug-এর ধরন: দেখতে নিরপেক্ষ মনে হওয়া একটা utility function আসলে ভেতরে ভেতরে একটা শক্তিশালী, অনিচ্ছাকৃত পক্ষপাত বহন করে। দ্বিতীয়ত, প্রতিটা user-কে নিজস্ব আলাদা action-value table দেওয়ায় শেখার অভিজ্ঞতা ভেঙে টুকরো টুকরো হয়ে গিয়েছিল — প্রতিটা user-এর table শুধু সেই একজনের transition থেকেই আপডেট হতো — তাই user-দের মধ্যে অভিজ্ঞতা একসাথে জমা করলে যত দ্রুত converge হতো, তার চেয়ে অনেক ধীরে converge হচ্ছিল।

**Fix:** একটা স্পষ্ট, ইচ্ছাকৃত tie-breaking নিয়ম বসানো হলো (নিরাপদ, no-op পছন্দের দিকে ঝোঁকানো, যেনতেন index-এর বদলে), আর যেখানে প্রাসঙ্গিক সেখানে user-দের মধ্যে শেখা ভাগ করে দেওয়া হলো।

**শিক্ষা:** দেখতে নিরপেক্ষ একটা utility function-এর একটা bug পুরো experiment-এর result-কে গ্রাস করে ফেলতে পারে। সংশোধিত tie-breaking function পরবর্তী প্রতিটা version-এর জন্য একটা স্থায়ী, পুনর্ব্যবহৃত utility হয়ে থেকে গেল।

### 4.2 v2–v3: "No-Op Imitation"-এর ফাঁদ

পরের iteration-গুলো do-nothing action-এর দিকে training-কে ঠেলে দেওয়ার চেষ্টা করল, আর স্থিতিশীলতা বাড়াতে বাড়তি shaping reward যোগ করল।

**Red flag:** সবচেয়ে বেশি বায়াসড configuration-গুলো টেস্ট করা সবকিছুর মধ্যে *সবচেয়ে খারাপ* performance দেখাল — কিছু না করার চেয়েও খারাপ।

**মূল কারণ:** একটা offset-based action space-এ (যেখানে action 0 মানে "বর্তমান অনুমানে কোনো পরিবর্তন কোরো না"), no-op action-এর দিকে একটা policy-কে ঠেলে দিলে সে সতর্ক হতে শেখে না — বরং সে তার অনুমান জমাট বেঁধে ফেলতে শেখে, এমন একটা channel অনুসরণ করা বন্ধ করে দেয় যা বাস্তবে অনবরত বদলাচ্ছে। একটা no-op-এর দিকে ঝুঁকে থাকা agent পুরোপুরি adapt করা বন্ধ করে দেয়, যা পূর্ণ adaptation বা এমনকি সম্পূর্ণ random আচরণের চেয়েও খারাপ।

**Fix:** no-op-এর দিকে ঝোঁক আর shaping bonus পুরোপুরি সরিয়ে ফেলা হলো।

**শিক্ষা:** "নিরাপদ আচরণ পছন্দ করো" — এই উদ্দেশ্যে বসানো একটা bias আসলে দাঁড়াতে পারে "তোমার কাজ করাই বন্ধ করো"-তে, যদি যা নিরাপদ মনে হচ্ছে তা প্রকৃত পরিস্থিতিতে যা মনে হচ্ছে তা না বোঝায়। Shaping reward-গুলো আসলে কী incentivize করছে, সেটা যাচাই করা দরকার — শুধু শুনতে কেমন উৎসাহজনক লাগছে, তা নয়।

### 4.3 v4: একটা স্থির Reference-এর সাপেক্ষে Action পুনর্লিখন

এই version-এ Part 3.4-এ বর্ণিত OLLA-relative encoding-এর একটা পূর্বসূরি introduce করা হলো: action-গুলোকে একটা fixed, static reference mapping-এর offset হিসেবে নতুন করে সংজ্ঞায়িত করা হলো, শূন্য থেকে করা absolute MCS choice-এর বদলে।

**ফলাফল:** প্রথমবারের মতো, একটা trained deep-learning policy raw throughput-এ OLLA-কে সামান্য ছাড়িয়ে গেল।

**একই সাথে করা সহগামী fix:** BLER waterfall curve (Part 1.2) আরও বাস্তবসম্মত আকারে recalibrate করা হলো; CQI reporting pipeline-এ feedback delay ও measurement noise ঢোকানো হলো (এতদিন simulation অবাস্তবভাবে পরিষ্কার ছিল); আর বেশ কিছু প্রচলিত deep-RL training-stability কৌশল প্রয়োগ করা হলো — একটা finite episode-এর শেষে সঠিকভাবে value estimate bootstrap করা, আর policy gradient হিসাবে ব্যবহৃত "advantage" signal-কে standardize করা (দুটোই actor-critic training-কে জর্জরিত করা high variance-এর জন্য পরিচিত সমাধান)।

**শিক্ষা:** Relative action encoding (এই baseline-relative আকারে) absolute action selection-এর চেয়ে উল্লেখযোগ্যভাবে বেশি সুশৃঙ্খল formulation প্রমাণিত হলো — একটা শিক্ষা যা এগিয়ে নিয়ে যাওয়া হলো, আর পরে v6-এ ব্যবহৃত OLLA-relative আকারে আরও পরিশীলিত করা হলো।

### 4.4 v5: একটা "অসম্ভব" Result দুটো গভীরতর Bug প্রকাশ করল

v4-এর প্রতিশ্রুতিশীল result বিশ্বাস করার আগে, সেটা আবার audit করা হলো।

**Red flag:** OLLA-কে naive baseline ১৬০%-এরও বেশি মার্জিনে হারিয়েছে বলে মাপা হলো — এমন একটা সংখ্যা, যা physically অসম্ভব একটা control loop-এর জন্য, যেটা নিজের design অনুযায়ী প্রতি step-এ শুধু ছোট ছোট ধাপে তার offset নাড়াতে পারে। একটা অবিশ্বাস্য রকম বড় positive result ঠিক ততটাই সন্দেহজনক, যতটা একটা খারাপ result — সাধারণত এর মানে দাঁড়ায় *পরিমাপের pipeline*-এ কোথাও গণ্ডগোল আছে, underlying phenomenon-এ নয়।

**মূল কারণ ১ — একটা scheduler information leak:** resource-scheduling logic (যেটা একটা নির্দিষ্ট TTI-তে কোন user transmit করার সুযোগ পাবে তা ঠিক করে, তাদের সাম্প্রতিক throughput history দেখে — Part 7.1-এ আলোচিত Proportional Fair scheduler দ্রষ্টব্য) একটা wiring ভুলের কারণে scheduling decision নেওয়ার সময় একটা transmission attempt-এর *প্রকৃত, ভবিষ্যৎ* ফলাফল দেখার সুযোগ পেয়ে গিয়েছিল — যেখানে দেখার কথা ছিল শুধু scheduling-এর মুহূর্তে যা প্রকৃতই available ছিল। এতে scheduler নীরবে সেই policy-কে সুবিধা দিতে পারত, যেটা বেশি aggressive হতো, সেই aggression আসলে ভালো সিদ্ধান্ত ছিল কি না তা নির্বিশেষে — অনেকটা একটা backtested trading strategy-তে lookahead bias-এর মতো, যেখানে "ভবিষ্যৎ"-এর তথ্য এমন একটা সিদ্ধান্তে ঢুকে পড়ে, যার শুধু "অতীত" দেখার কথা ছিল।

**মূল কারণ ২ — একটা reward-জনিত "prisoner's dilemma":** reward গুলো cell-level-এ একত্র না করে per-user ভিত্তিতে হিসাব হচ্ছিল, যা একটা বিকৃত প্রণোদনা তৈরি করেছিল: একটা user (বা তার হয়ে কাজ করা policy) নিজের channel quality বাড়িয়ে report করে scheduling-এ সুবিধা পেতে পারত, কারণ বেশি আশাবাদী একটা report সেই user-কে schedule করার জন্য বেশি আকর্ষণীয় করে তুলত — যদিও এতে সেই user-এরই transmission failure-এর ঝুঁকি বেড়ে যেত। এটা একেবারে multi-agent incentive-misalignment সমস্যার একটা উদাহরণ: এমন একটা reward structure, যা individually স্বার্থপর আচরণকে পুরস্কৃত করে গোষ্ঠীগত ফলাফলের মূল্যে, যদিও প্রতিটা agent একই network resource ভাগ করে নিচ্ছে।

**Fix:** scheduler-কে শুধু সেই তথ্য দেখতে দেওয়া হলো, যা decision-এর মুহূর্তে প্রকৃতই available (*reported* channel quality, প্রকৃত channel quality নয়), আর একটা একক, একত্রিত, সহযোগিতামূলক cell-level reward-এ পরিবর্তন করা হলো, যা প্রতিটা user-এর learning update দিয়ে ভাগ করে নেওয়া হয় — এতে misreport করার প্রণোদনাই উবে যায়।

**শিক্ষা:** অবিশ্বাস্য রকম *ভালো* একটা result ঠিক ততটাই forensic যাচাইয়ের দাবি রাখে, যতটা একটা অবিশ্বাস্য রকম খারাপ result রাখে। Scheduler information leakage আর misaligned multi-agent incentive — এই দুটোই যেকোনো multi-user RL system-এ সক্রিয়ভাবে খুঁজে দেখার মতো পুনরাবৃত্ত failure mode, শুধু এই একটাতেই নয়।

### 4.5 v6: OLLA-Relative Encoding দিয়ে Information Gap বন্ধ করা

v5-এর scheduler আর reward bug ঠিক হওয়ার পর, সৎ result দাঁড়াল এই যে RL শুধু OLLA-কে *match* করছে, হারাচ্ছে না।

**নির্ণয়:** OLLA-র হাতে আছে দ্রুত, per-transmission ACK/NACK feedback (Part 2.2), যেটা v5-এর সেটআপে RL agent-এর নিজের observed state-এ একদমই expose করা হচ্ছিল না। এটা একটা তথ্যগত অসামঞ্জস্য, প্রকৃত কোনো ক্ষমতার ফারাক নয় — OLLA বেশি বুদ্ধিমান ছিল না, সে শুধু এমন কিছু জানত যা learner-কে বলাই হয়নি।

**Fix:** Part 3.4-এ introduce করা OLLA-relative action encoding — প্রতিটা learner-কে (আর পরে তৈরি হওয়া প্রতিটা comparator-কে) নিজের মধ্যে একই OLLA loop দাও, RL action-কে তার ওপর একটা correction হিসেবে সংজ্ঞায়িত করো, আর বর্তমান OLLA offset-কেই observed state-এর অংশ হিসেবে expose করো।

**ফলাফল:** এটাই সেই version, যা শেষ পর্যন্ত একটা সত্যিকারের ন্যায্য, apples-to-apples তুলনা তৈরি করল — এবং, পরের অংশে বর্ণিত হিসেবে, এই ন্যায্য তুলনার আওতাতেও এর *আপাত* সাফল্য অসম্পূর্ণ প্রমাণিত হলো, আরেকটা control যোগ করার পর।

চার-round-এর এই history — একটা tie-breaking bug থেকে শুরু করে, একটা reward-shaping-এর ফাঁদ পেরিয়ে, দুই রকমের information leakage পর্যন্ত, শেষে গুরুত্ব দেওয়ার মতো একটা version-এ পৌঁছানোর আগে — এই কারণেই v6, v1 নয়, "এই approach আসলেই কাজ করে কি না" জিজ্ঞেস করার উপযুক্ত শুরুর বিন্দু। এই round-গুলোয় গড়ে ওঠা অভ্যাসটাই — প্রতিটা বিস্ময়কর সংখ্যাকে, ভালো হোক বা খারাপ, তদন্ত করার মতো একটা সূত্র হিসেবে দেখা, মেনে নেওয়ার মতো একটা result হিসেবে নয় — সরাসরি বহন করে নিয়ে যাওয়া হয়েছে v6-থেকে-v7-এর গল্পে, যা আসছে পরের অংশে।

---

## Part 5: v6 থেকে পাওয়া অস্বস্তিকর শিক্ষা

### 5.1 v6 কী খুঁজে পেল

Pipeline অবশেষে ভরসাযোগ্য হওয়ার পর (Part 4.5), v6 Part 3.4-এ বর্ণিত OLLA-relative RL সেটআপ চালাল, আর দেখল একটা neural-network policy — actor-critic RL algorithm দিয়ে trained — statistically significant মার্জিনে plain OLLA-কে হারাচ্ছে। বেশ কিছু feedback-delay setting-এ কয়েক percent বেশি throughput, formal hypothesis test দিয়ে নিশ্চিত করা।

উপর থেকে দেখলে, এটাই ঠিক সেই positive result, যা Part 3.3-এর hypothesis অনুমান করেছিল।

### 5.2 যে Control সবকিছু বদলে দিল

ভালো experimental design শুধু জিজ্ঞেস করে না "আমার sophisticated method কি একটা naive baseline-কে হারায়?" — বরং জিজ্ঞেস করে, "আমার sophisticated method কি *সবচেয়ে সহজ যে জিনিসটা ভাবা সম্ভব*, তাকে হারায়?" এটা machine-learning-এর null hypothesis test-এর সমতুল্য, বা Occam's razor-এর: একটা জটিল model-কে প্রকৃত insight-এর কৃতিত্ব দেওয়ার আগে, প্রমাণ করতে হয় যে এর চেয়ে অনেক সহজ একটা model একই result অর্জন করছে না।

এখানে প্রাসঙ্গিক "সহজ model"-টা হলো একটা **constant**: state দেখে সিদ্ধান্ত নেওয়া একটা neural network-এর বদলে, শুধু একটা fixed সংখ্যা বেছে নাও — একটা একক, অপরিবর্তনীয় correction offset — আগে থেকে calibrate করা (আলাদা data-তে, final comparison-এ ব্যবহৃত trace-এ নয়, যাতে ন্যায্যতা বজায় থাকে), আর তারপর সবসময়, একই রকমভাবে প্রয়োগ করা, environment-এ যা কিছুই ঘটুক না কেন। একটা constant, সংজ্ঞা অনুযায়ীই, state-এর ওপর নির্ভর করতে পারে না। এটা adapt করতে পারে না। Predict করতে পারে না। প্রকৃত অর্থে এটাই সবচেয়ে সহজ policy, যদিও আক্ষরিক অর্থে "কিছুই না করা" নয়।

এই control যখন v6-এর evaluation-এ যোগ করা হলো, তখন এটা neural network-এর throughput-এর সাথে মিলে গেল। **যে policy দেখতে পারে না, চিন্তা করতে পারে না, adapt করতে পারে না — সে ঠিক একই performance দিল, যাকে বিশেষভাবে দেখতে, চিন্তা করতে আর adapt করতে তৈরি করা হয়েছিল।**

### 5.3 কেন এটা এত গুরুত্বপূর্ণ

এটা result-এর কোনো ছোট টীকা নয় — এটা result-এর *অর্থটাই* বদলে দেয়। একটা constant যদি neural policy-র মতোই throughput অর্জন করতে পারে, তাহলে neural policy যে "OLLA-কে হারাচ্ছে" — সেটা পুরোপুরি ব্যাখ্যা করা যায় **operating point কোথায় বসানো হয়েছে**, তা দিয়ে (মোটের ওপর: OLLA-র নিজস্ব default equilibrium-এর চেয়ে একটু বেশি গরম বা aggressive ভাবে চালানো) — network যে *বিভিন্ন পরিস্থিতিতে ভিন্নভাবে কাজ করতে শিখেছে*, এমন কিছু নয়। এই গাইডের বাকি অংশে এর জন্য ব্যবহৃত শব্দটা হলো **setpoint effect**: পুরো measured gain-টা আসলে একটা single scalar shift, state-conditional adaptivity-র কোনো প্রমাণ নয়।

এটা ঠিক সেই ধরনের finding, যা মিস করলে একটা overclaimed publication-এর দিকে নিয়ে যেত: "আমরা দেখাই RL industry-standard OLLA-কে X% হারায়" — শুনতে impressive, আর *একটা সত্য statement*, কিন্তু এটা একটা ভুল সিদ্ধান্তকে আমন্ত্রণ জানায় (যে network কিছু চতুর আর পরিস্থিতি-সংবেদনশীল শিখেছে), যা একটা যথাযথ control ছাড়া সমর্থিত নয়। Publication-এর *আগে* এটা ধরা, পরে নয় — constant-offset control চালানোর পুরো মূল্যটাই এখানে।

এটা স্বাভাবিকভাবেই পরের প্রশ্ন তুলে ধরে: **কেন v6-এর নির্দিষ্ট environment-এ একটা constant-ই যথেষ্ট হয়ে গেল?** সেটার diagnostic উত্তর খোঁজাই সরাসরি নিয়ে গেল সেই redesign-এর দিকে, যা পরিণত হলো v7-এ।

---

## Part 6: Test-কে পুনর্গঠন — v7-এর পাঁচটা লিভার

কেন v6-এ একটা constant-ই যথেষ্ট হলো, তা diagnose করতে হলে দেখতে হবে ঠিক কোন কোন simplification v6-এর simulation environment করেছিল, আর জিজ্ঞেস করতে হবে: প্রতিটা simplification কি এমন কোনো *কারণ* সরিয়ে দিয়েছিল, যার জন্য একটা state-conditional policy সুবিধা পেত? এমন চারটা simplification চিহ্নিত করা হলো, আর v7 একসাথে এই চারটাই সরিয়ে দেয় (আর সাথে একটা information-theoretic control যোগ করে, মোট পাঁচটা পরিবর্তনের জন্য), নিচের যুক্তিতে।

### 6.1 (D1) Error-এর কোনো মূল্য নেই — HARQ ও Retransmission যোগ করা

v6-এ, একটা ব্যর্থ transmission-কে শুধু throughput-এর একটা probabilistic ছাড় হিসেবে score করা হতো — failure-এর সরাসরি probability ছাড়া আর কোনো মূল্য চোকাতে হতো না, এমন কোনো mechanism ছিল না। এতে একটা বিকৃত প্রণোদনা তৈরি হয়: যেহেতু failure-এর কোনো বাড়তি penalty নেই, throughput সর্বোচ্চ করার কৌশল হয়ে দাঁড়ায় নিছক "যতটা সম্ভব aggressive হও, আর গড়টা মিলিয়ে নাও" — পরিস্থিতি বুঝে সংযত থাকাকে কখনো পুরস্কৃত না করেই।

Fix হলো **Hybrid Automatic Repeat Request (HARQ)** যোগ করা: একটা transmission fail করলে, receiver সেটা ফেলে দেয় না — বরং corrupted data রেখে দেয়, আর একই block-এর একটা retransmission-এর সাথে মিলিয়ে নেয়, একে বলে **chase combining**, যা retry-র effective SINR বাড়িয়ে দেয় (এখানে model করা হয়েছে প্রতিটা আগের attempt-এর জন্য $+2.5$ dB বাড়তি হিসেবে, সর্বোচ্চ ৩টা attempt পর্যন্ত, তারপর ছেড়ে দেওয়া হয়)। গুরুত্বপূর্ণ বিষয় হলো, সেই retransmission একটা প্রকৃত time slot খরচ করে, যা অন্যথায় কারো নতুন data বহন করতে পারত। এখন একটা অতিরিক্ত-aggressive প্রথম চেষ্টার একটা প্রকৃত মূল্য আছে — retry-তে নষ্ট হওয়া capacity — যা একটা প্রকৃত trade-off তৈরি করে: "দ্রুত transmit করো, একটা costly retry-র ঝুঁকি নাও" বনাম "সতর্কভাবে transmit করো, প্রতিটা slot নতুন data-র জন্য ব্যবহার করো"। এটাই ঠিক সেই ধরনের trade-off, যা একটা বুদ্ধিমান, পরিস্থিতি-সচেতন policy-র, নীতিগতভাবে, একটা fixed নিয়মের চেয়ে ভালোভাবে সামলানোর কথা।

### 6.2 (D2) প্রতিটা User এক রকম — Heterogeneity যোগ করা

v6-এ প্রতিটা user-এর একই feedback delay আর একই mobility profile ছিল। সেই পরিস্থিতিতে একটা calibrated constant, স্বতঃসিদ্ধভাবেই, প্রতিটা user-এর জন্য optimal — কারণ user-দের মধ্যে exploit করার মতো কোনো ভিন্নতাই নেই।

v7-এ প্রতিটা user স্বাধীনভাবে একটা feedback delay (2–8 TTI) আর speed (3–30 m/s) পায়। এখন একটা *একক* constant একই সাথে একজন ধীরগতির user-এর জন্য (যার দ্রুত, নির্ভুল feedback আছে) আর একজন দ্রুতগামী user-এর জন্য (যার ধীর, পুরনো feedback আছে) — উভয়ের জন্যই optimal হতে পারে না। এতে সরাসরি এমন একটা পথ খুলে যায়, যেখানে adaptivity — এমনকি শুধু "কোন user-এর সাথে কথা বলছ তা জানো, আর সেই অনুযায়ী কাজ করো" হলেও — উপকারী হতে পারে।

### 6.3 (D3) Trace-এর মধ্যে কিছুই বদলায় না — Non-Stationarity যোগ করা

Environment-এর পরিসংখ্যান যদি একটা observed trace-এর মধ্যে কখনো না বদলায়, তাহলে একটা reactive integrator (OLLA) আর একটা static constant — দুটোই শেষ পর্যন্ত একই steady-state উত্তরে গিয়ে স্থির হবে। একটা predictive policy-র জন্য reactive policy-র চেয়ে দ্রুত react করার মতো কোনো *পরিবর্তনই* তখন থাকে না।

v7 introduce করে একটা randomly-timed, randomly-lasting **interference burst** — একটা two-state Markov chain হিসেবে model করা, যা বাড়তি interference-কে চালু আর বন্ধ করে — সাথে প্রতিটা user-এর mobility speed-এর একটা mid-trace পরিবর্তন। এগুলো ঠিক সেই ধরনের regime-পরিবর্তন, যেখানে একটা পুরোপুরি reactive controller গঠনগতভাবেই পিছিয়ে থাকে: OLLA যখন "টের পায়" (একের পর এক failure দেখে) যে পরিস্থিতি বদলে গেছে, ততক্ষণে বেশ কয়েকটা TTI-র suboptimal সিদ্ধান্ত ইতিমধ্যে ঘটে গেছে। একটা policy, যে OLLA-র integrator react করার চেয়ে দ্রুত, সূক্ষ্মতর ইঙ্গিত থেকে পরিবর্তনের শুরুটা ধরতে পারে, এখানেই তার মূল্য যোগ করার কথা।

### 6.4 (D4) পদার্থবিদ্যা বড্ড বেশি ক্ষমাশীল ছিল — Error Curve খাড়া করা, বাস্তবসম্মত Fading যোগ করা

v6 তুলনামূলকভাবে মৃদু একটা BLER-বনাম-SINR curve ব্যবহার করেছিল (Part 1.2-এর "waterfall" বর্ণনা মনে করুন) — মানে ideal MCS একটু ছাড়িয়ে গেলেও error probability-তে খুব বেশি মূল্য দিতে হতো না। v7 অনেক খাড়া একটা curve ব্যবহার করে, তাই MCS বাছাইয়ে নির্ভুলতা এখন সত্যিই গুরুত্বপূর্ণ হয়ে ওঠে।

আলাদাভাবে, v6 fading (multipath propagation-এর কারণে received signal strength-এর দ্রুত, random ওঠা-নামা) মডেল করেছিল একটা fixed statistical correlation দিয়ে, user কত দ্রুত চলছে তা নির্বিশেষে। এটা physically ভুল — একজন দ্রুতগামী user-এর channel সত্যিই দ্রুত decorrelate হয় (কম coherence time; Part 1.5 মনে করুন) — আর experiment-এর জন্য আরও গুরুত্বপূর্ণ কথা হলো, এতে নীরবে সেই physical সম্পর্কটাই বাদ পড়ে গিয়েছিল "user speed" আর "channel কতটা predictable" তার মধ্যে — যে সম্পর্কটা একটা speed-aware policy-র exploit করার জন্য দরকার হতো। v7 এটা ঠিক করে standard **Jakes fading model** ব্যবহার করে, প্রতিটা user-এর তাৎক্ষণিক speed থেকে সরাসরি channel-এর time-correlation coefficient বের করে, Doppler সম্পর্কের মাধ্যমে:

$$\rho_i(t) = J_0\!\left(2\pi \frac{v_i(t) f_c}{c} T_{\text{tti}}\right)$$

যেখানে $J_0$ প্রথম প্রকারের zeroth-order Bessel function (classical Jakes/Clarke scattering model-এর অধীনে Rayleigh fading-এর autocorrelation-এর জন্য standard closed-form result), $f_c$ carrier frequency, $c$ আলোর গতি, আর $T_{\text{tti}}$ TTI-র সময়কাল।

### 6.5 (D5) একটা Information Control: দুটো State "Tier"

শেষ পরিবর্তনটা environment-এ কোনো physical পরিবর্তন নয় — বরং একটা experimental control, Part 5.2-এর constant-offset control-এর মতোই একই চেতনায়, শুধু এবার একটা ভিন্ন সম্ভাব্য confound-কে target করে: RL-এর ব্যর্থতা (বা সাফল্য) কি আসলে *সঠিক তথ্য* দেওয়া হয়েছিল কি না তার ওপর নির্ভর করছে, adaptivity-র আদৌ কোনো মূল্য আছে কি না তার ওপর নয়?

v7 দুটো version সংজ্ঞায়িত করে, RL agent কী observe করতে পারবে তার:

- **Tier A**: ঠিক ততটুকু তথ্য, যতটুকু OLLA-র নিজের loop-এর হাতে আছে (মূলত CQI history আর বর্তমান offset ছাড়া আর কিছু না) — একটা "information-equal" baseline, যা নিশ্চিত করে এখানে পাওয়া যেকোনো RL advantage-কে "constant/OLLA comparator-দের হাতে যা নেই, সেই state-observation" দিয়ে দায়ী করা যাবে না।
- **Tier B**: Tier A, প্লাস পাঁচটা বাড়তি feature, যা কোনো scalar control loop নীতিগতভাবেও represent করতে পারে না — HARQ retry state, failure-এর একটা স্বল্পমেয়াদি history, SINR-এর সাম্প্রতিক trend, user-এর তাৎক্ষণিক speed, আর একটা (delayed) indicator যে এই মুহূর্তে কোনো interference burst চলছে কি না।

*একই* experiment দুই tier-এর অধীনে চালিয়ে result তুলনা করাটাই "সমৃদ্ধ তথ্য কি সাহায্য করে?" — এই প্রশ্নটাকে গাইডের বাকি সব প্রশ্ন থেকে আলাদা করার সবচেয়ে পরিষ্কার উপায়।

---

## Part 7: Experiment-কে Rigorous করার প্রক্রিয়া

পুরো campaign চালানোর আগে, design-টা লিখিতভাবে জমা দিয়ে ঠিক করা হয় কীভাবে success বিচার করা হবে — এই চর্চাকে বলে **pre-registration**। এটা ধার করা হয়েছে clinical trial থেকে, আর computational science-এ ক্রমশ গৃহীত হচ্ছে, বিশেষত একটা পরিচিত failure mode ঠেকাতে: data দেখার *পরে* যদি success criterion বেছে নেওয়ার সুযোগ থাকে, তাহলে প্রায় সবসময়ই *কোনো না কোনো* metric, subset, বা scheduler খুঁজে পাওয়া যাবে, যার আওতায় পছন্দের method ভালো দেখাবে, নিছক কাকতালীয়ভাবে। (এটা statistics-এর **multiple comparisons problem**-এর সাথে ঘনিষ্ঠভাবে সম্পর্কিত — data-কে যত বেশি উপায়ে কেটেকুটে significance খোঁজার সুযোগ দেওয়া হয়, কোথাও না কোথাও ভুয়া significance পাওয়ার সম্ভাবনা তত বাড়ে।)

### 7.1 আগে থেকে নির্ধারিত Win Condition

আগেভাগেই বলে রাখা হয়েছিল: **neural-network RL policy-কে অবশ্যই best-tuned constant offset-কে হারাতে হবে — per user class calibrate করা, industry-standard scheduling নিয়মের অধীনে (Proportional Fair, একটা scheduling policy যা user-দের মধ্যে throughput আর fairness-এর ভারসাম্য রাখে) — একটা paired statistical test-এ, significance level $p < 0.05$-এ।**

সেই বাক্যের প্রতিটা design choice-এরই একটা কারণ আছে:

- **Comparator একটা constant, শুধু OLLA নয়।** Part 5-এ প্রতিষ্ঠিত হয়েছে যে, শুধু OLLA-র বিরুদ্ধে জেতা খুব দুর্বল একটা মাপকাঠি — এতে "কিছু চতুর শিখেছে" আর "একটা ভালো setpoint খুঁজে পেয়েছে"-এর মধ্যে পার্থক্য বোঝা যায় না। RL agent যেসব representative data-তে train হয়, সেই একই ধরনের data দিয়ে calibrate করা constant, অনেক বেশি দাবিদার আর সৎ একটা মাপকাঠি।
- **Per user class ("FixedPU"), কোনো একক global constant নয়।** Part 6.2 মনে করুন: heterogeneity মানেই একটা একক global constant প্রমাণসাপেক্ষে suboptimal। একটা *per-class* constant-এর (ছয়টা constant — দুইটা delay category আর তিনটা speed category-র প্রতিটা combination-এর জন্য একটা করে) বিরুদ্ধে তুলনা করলে সহজ একটা ফাঁক বন্ধ হয়ে যায়: "RL শুধু ভিন্ন user-দের আলাদাভাবে treat করতে শিখেই জিতে যাচ্ছে" — যা user identity-র ওপর ভিত্তি করা একটা লুকআপ টেবিলও করতে পারত, কোনো real state-conditioning ছাড়াই।
- **একটা নির্দিষ্ট scheduler (PF)।** এটাই deployed network-এ প্রকৃতপক্ষে ব্যবহৃত scheduler; শুধু একটা অবাস্তব scheduling নিয়মের অধীনে সত্য এমন একটা result-এর প্রাসঙ্গিকতা সীমিত হতো। (অন্য scheduler-ও মাপা আর report করা হয়েছে, শুধু pass/fail criterion ঠিক করতে ব্যবহার করা হয়নি।)
- **$p<0.05$-এ একটা paired statistical test।** "Paired" মানে প্রতিটা scheme-কেই *ঠিক একই* সেট-এর held-out test scenario-তে যাচাই করা হয় (৩০টা স্বাধীনভাবে তৈরি করা "trace" — random user population আর channel realization, যা training বা calibration-এর সময় কখনো দেখা যায়নি)। এতে অনেকটা noise বাদ পড়ে যায়, যা অন্যথায় গড় করে ফেলতে হতো — আপনি সরাসরি scheme A-র score-এর সাথে scheme B-র score তুলনা করছেন *একই পরিস্থিতিতে*, trace-বাই-trace, আলাদা করে গড় করা দুটো সংখ্যা তুলনা করার বদলে। ব্যবহৃত নির্দিষ্ট test, **Wilcoxon signed-rank test**, paired t-test-এর একটা nonparametric বিকল্প — এটা ধরে নেয় না যে underlying পার্থক্যগুলো normally distributed, যা এখানে একটা নিরাপদ ধারণা, কারণ throughput-এর distribution bounded আর প্রায়ই skewed। $p<0.05$-এর একটা result মানে: দুই scheme-এর মধ্যে সত্যিই কোনো পার্থক্য না থাকলেও, এত বড় (বা তার চেয়েও বড়) একটা effect নিছক কাকতালীয়ভাবে ঘটার সম্ভাবনা ৫%-এরও কম — "statistically significant" বলার জন্য প্রচলিত (কিছুটা arbitrary হলেও) একটা মাপকাঠি।

### 7.2 কেন একটা নয়, নয়টা আলাদা Experiment চালানো হলো

পুরো campaign নয়টা ভিন্ন operating point-এ এই তুলনা চালায়: একটা শান্ত, homogeneous baseline (কঠিন result বিশ্বাস করার আগে সাধারণ implementation bug ধরতে); heterogeneity-র দুইটা level, আলাদাভাবে; interference-burst intensity-র তিনটা level; Tier-A information-equal ablation; একটা version, যেখানে OLLA-কে score শুরু হওয়ার আগে steady state-এ পৌঁছানোর জন্য একটা লম্বা "head start" দেওয়া হয় (একটা ইচ্ছাকৃতভাবে RL-এর জন্য অসুবিধাজনক control); আর সম্পূর্ণ ভিন্ন random seed দিয়ে main result-এর একটা স্বাধীন পুনরাবৃত্তি।

এই বিস্তৃতির পেছনের যুক্তি: যেকোনো একটা একক experiment sampling variance থেকে একটা বিভ্রান্তিকর result দেখাতে পারত — random channel আর training-এর randomness-এর একটা দুর্ভাগ্যজনক (বা সৌভাগ্যজনক) draw। *একই underlying hypothesis*-কে অনেকগুলো ভিন্ন পরিস্থিতিতে চালিয়ে, আর সবগুলো জুড়ে একটা *সামঞ্জস্যপূর্ণ pattern* খোঁজাটাই, যেকোনো একটা একক সংখ্যার চেয়ে অনেক বেশি বিশ্বাসযোগ্য। RL agent যদি কোথাও সত্যিকারের একটা advantage খুঁজে পেত, এই design তাকে সেটা দেখানোর অনেক স্বাধীন সুযোগ দিত।

---

## Part 8: কী ঘটল — Headline Result

সম্পূর্ণ নয়-point campaign চালানো হলো, প্রতিটা method-কে (একটা সাধারণ reactive baseline, OLLA, global constant, per-class constant, দুইটা tabular RL algorithm, আর deep neural-network RL agent) একাধিকবার শূন্য থেকে train করে (ভিন্ন random seed দিয়ে), আর প্রতিটাকে একই held-out test trace-এ, ঠান্ডা মাথায়, যাচাই করে।

**Result: নয়টার মধ্যে শূন্যটা experiment pre-registered win condition পাস করল।** Neural network কখনোই primary scheduler-এ statistical significance-এ per-class constant-কে হারায়নি; নয়টার মধ্যে তিনটাতে সে significantly হেরেছে। তবে, সে ধারাবাহিকভাবে plain OLLA-কে হারিয়েছে — কয়েক percent থেকে শুরু করে দশ percent-এরও বেশি, প্রায়ই উঁচু statistical significance-এ।

প্রথম দেখায় মনে হয় এটা v6-এর একই শিক্ষার পুনরাবৃত্তি: "OLLA-কে হারায়" দাবিটা টিকে থাকে, কিন্তু "সৎ, হারানো কঠিন comparator-কে হারায়" দাবিটা টেকে না — এমনকি v6-এ এই pattern-এর জন্য দায়ী বলে চিহ্নিত চারটা simplification specifically সরিয়ে environment পুনর্গঠন করার পরেও।

**কিন্তু এখানে একটা গুরুত্বপূর্ণ পদ্ধতিগত ভাগ তৈরি হয়:** এই ধরনের একটা null result-এর অন্তত দুটো খুবই ভিন্ন সম্ভাব্য ব্যাখ্যা থাকতে পারে, আর তারা সম্পূর্ণ ভিন্ন প্রতিক্রিয়া দাবি করে:

- **(a)** এই ধরনের সমস্যায় সত্যিই exploit করার মতো কোনো adaptivity value নেই — constant সত্যিই optimal-এর কাছাকাছি, আর সৎ scientific সিদ্ধান্ত হলো একটা ভালোভাবে সমর্থিত negative result।
- **(b)** experimental *pipeline নিজেই*-তে কিছু একটা — একটা bug, একটা mismatch, code-এর মধ্যে লুকানো একটা অন্যায্য তুলনা — RL agent-কে তার প্রকৃত অর্জনযোগ্য performance-এ পৌঁছাতে বাধা দিচ্ছে, আর null result সেই ত্রুটিরই একটা প্রতিফলন, underlying সমস্যা সম্পর্কে কোনো সত্য নয়।

এই দুটো বাইরে থেকে একই রকম দেখায় (দুটোই তৈরি করে "৯টার মধ্যে ০টা"), কিন্তু এর মধ্যে শুধু একটাই বিশ্বাসযোগ্য scientific finding। এদের আলাদা করার একমাত্র দায়িত্বশীল উপায় হলো, (b)-র প্রমাণের জন্য নিয়মমাফিক খোঁজা — শুধু null মেনে নিয়ে লিখে ফেলা নয়, আর একই ত্রুটিপূর্ণ pipeline বারবার চালিয়ে ভিন্ন উত্তর আশা করাও নয়।

---

## Part 9: গোয়েন্দাগিরি

এই অংশটা, মূলত, একটা debugging-এর গল্প — কিন্তু নিয়মশৃঙ্খলাযুক্ত একটা গল্প, যেখানে প্রতিটা ধাপ চালিত হয়েছে একটা নির্দিষ্ট, falsifiable প্রশ্ন দিয়ে, এলোমেলো ঘাঁটাঘাঁটি দিয়ে নয়। এটা Part 4-এ প্রতিষ্ঠিত v1–v5-এর history-র একই শৃঙ্খলা অনুসরণ করে।

### 9.1 দুটো Method কি আসলেই ন্যায্যভাবে তুলনা করা হচ্ছে?

"method A method B-র কাছে হেরে যায়" — এমন যেকোনো result-এ প্রথমেই যা যাচাই করা উচিত, তা হলো A আর B-কে আসলে তুলনীয় সম্পদ আর পরিস্থিতি দেওয়া হয়েছিল কি না। Per-class constant calibrate করা code পরীক্ষা করে দেখা গেল, এটা *শুধুমাত্র* primary scheduler (PF) ব্যবহার করে tune করা হয়েছিল — ঠিক সেই পরিস্থিতি, যা pre-registered test মাপে। কিন্তু RL training code পরীক্ষা করে দেখা গেল, neural network তার training সময় *তিনটা* ভিন্ন scheduler-এর মধ্যে ভাগ করেছে (50% PF-এ, বাকি দুটোতে 25% করে)। **Comparator ঠিক test পরিস্থিতির জন্যই বিশেষায়িত ছিল; learner ছিল না।** এটা কোনো সূক্ষ্ম statistical খুঁত নয় — এটা দুই student-কে একই পরীক্ষায় নম্বর দেওয়ার মতো, যেখানে শুধু একজনকে বলা হয়েছিল কোন পরীক্ষা হতে যাচ্ছে।

### 9.2 Learner কি আসলেই Comparator-এর উত্তরটা তুলে ধরতে পারে?

Best constant offset খোঁজার জন্য calibration search চালানো হয়েছিল একটা সীমিত সাংখ্যিক range-এ। দেখা গেল, *বেছে নেওয়া* best offset সেই search করা range-এর একদম *প্রান্তে* বসে ছিল — যেকোনো optimization procedure-এই এটা একটা চেনা সতর্কতা-সংকেত, যার মানে প্রকৃত optimum হয়তো search করা range-এর বাইরে (ধরুন, আপনি শুধু ০ থেকে ১০-এর মধ্যে দেখলেন, আর সেরা যে value পেলেন তা ১০ — তাহলে প্রকৃত সেরাটা সম্ভবত ১০-এর ওপরেই)। আরও খারাপ, range ঠিকমতো বিস্তৃত করার পর দেখা গেল, একটা user category-র প্রকৃত optimal offset সম্পূর্ণভাবেই সেই *action set*-এর বাইরে পড়ে, যা neural network-কে বেছে নেওয়ার সুযোগও দেওয়া হয়নি। **Comparator-এর প্রকৃত সেরা উত্তরটাই, আক্ষরিক অর্থে, learner-কে কখনো দেওয়াই হয়নি এমন একটা option ছিল।**

### 9.3 Network কি শুধু Undertrained?

Training-এর পর network-এর performance-কে তুলনা করা হলো এমন একটা policy-র বিরুদ্ধে, যা network by construction নিখুঁতভাবে তুলে ধরতে সক্ষম (মনে করুন: action $0$ এটাকে OLLA-র মতোই আচরণ করায়, আর এটা নীতিগতভাবে প্রতিবার একই constant action output করতে শিখতে পারত, যেহেতু এটা একটা neural network যা প্রকাশ করতে পারে তারই একটা সহজ, বিশেষ ক্ষেত্র মাত্র) — তবু trained network এমন একটা জায়গায় গিয়ে থেমে গেল, যা constant-এর অর্জনের চেয়ে *নিচে*। একটা model, যে তার নিজের expressive ক্ষমতার মধ্যেই একটা policy ভালোভাবে match করতে ব্যর্থ হয়, সেটা একটা optimization সমস্যার লক্ষণ (খারাপ initialization, অপর্যাপ্ত training, দুর্বল exploration) — underlying কাজটা কতটা কঠিন, তার প্রমাণ নয়।

### 9.4 শুধু Training Log পড়েই খুঁজে পাওয়া একটা সূক্ষ্মতর Bug

9.3-এর সমস্যার জন্য একটা চেষ্টা করা fix ছিল network-কে **warm-start** করানো: trial and error দিয়ে স্বাধীনভাবে শিখতে দেওয়ার আগে, প্রথমে calibrated constant-এর সিদ্ধান্তগুলো সরাসরি অনুকরণ করতে train করা (একটা প্রচলিত machine-learning কৌশল, যাকে বলে **behavior cloning** — মূলত, "expert এখানে কী করত" তার ওপর supervised learning, যা reinforcement learning proper-এ যাওয়ার আগে একটা initialization হিসেবে ব্যবহৃত হয়)।

এটা একটা যুক্তিসঙ্গত ধারণা, কিন্তু *result আরও খারাপ হলো*, ভালো নয়। এটা নিজেই তথ্যবহুল: যে fix জিনিসগুলোকে আরও খারাপ করে দেয়, তার মানে সাধারণত হলো নতুন একটা bug ঢুকে গেছে — underlying ধারণাটা ভুল ছিল, তা নয়। তাই পরের ধাপ ছিল raw, per-episode training log পড়া, শুধু চূড়ান্ত summary সংখ্যা নয়।

Log-গুলোই mechanism-টা নিখুঁতভাবে ফাঁস করে দিল। **Entropy**, RL-এর ভাষায়, মাপে একটা policy-র action choice কতটা random বা ছড়ানো — একটা policy, যে সবসময় একই action deterministically বেছে নেয়, তার entropy শূন্য; আর একটা policy, যে সব action-এর মধ্যে সমানভাবে random বেছে নেয়, তার entropy সর্বোচ্চ। Behavior-cloning phase সফলভাবে policy-র entropy-কে প্রায় শূন্যে নামিয়ে এনেছিল (constant-এর একটা confident, deterministic অনুকরণ, ঠিক যেমনটা উদ্দেশ্য ছিল)। কিন্তু reinforcement-learning fine-tuning শুরু হওয়ার সাথে সাথেই, পরের episode-গুলোতে entropy *সাথে সাথেই আবার সর্বোচ্চের দিকে* উঠতে শুরু করল।

কারণটা এই: RL training সাধারণত exploratory (উচ্চ-entropy) আচরণ ধরে রাখার জন্য একটা ছোট bonus reward রাখে, যাতে policy যথেষ্ট explore করার আগেই কোনো খারাপ সিদ্ধান্তে আটকে না যায় — একটা প্রচলিত, সাধারণত যুক্তিসঙ্গত কৌশল। কিন্তু এই exploration bonus এমনভাবে schedule করা ছিল, যাতে fine-tuning phase-এর *শুরুতেই* তার *সর্বোচ্চ* শক্তিতে চালু হয়ে যায় — এই বিবেচনা না করেই যে সেই phase-এ আসা policy-টা ইতিমধ্যেই একটা যত্ন করে গড়া, তথ্যবহুল অনুকরণ, কোনো সদ্য-শুরু random network নয়। ফলে fine-tuning প্রক্রিয়াটা কার্যকরভাবে, behavior-cloning phase মাত্র যা শিখিয়েছিল, সেই উপকারী জিনিসটাই সক্রিয়ভাবে *ভুলিয়ে দিচ্ছিল*।

এটা সত্যিই একটা সূক্ষ্ম failure mode, আর এটা ধরার একমাত্র উপায় ছিল aggregate result ছাড়িয়ে গিয়ে প্রকৃত training dynamics পরীক্ষা করা — একটা কাজে লাগার মতো সাধারণ শিক্ষা: একটা machine learning experiment যখন একটা বিস্ময়কর negative result দেয়, raw learning curve-ই (শুধু চূড়ান্ত score নয়) প্রায়শই সেই জায়গা, যেখানে প্রকৃত ব্যাখ্যাটা লুকিয়ে থাকে।

---

## Part 10: ধাপে ধাপে এটা ঠিক করা

### 10.1 প্রথম চেষ্টা: স্পষ্ট সমস্যাগুলো ঠিক করা

Fix-এর প্রথম round-টা address করল 9.1 (comparator যে একটা scheduler-এই calibrate হয়েছিল, সেখানেই RL-কেও train করা), 9.2 (calibration search range আর network-এর action set — দুটোই বিস্তৃত করা), আর 9.3 (behavior-cloning warm start যোগ করা)। Result: তারপরও একটা loss, আর কোনো fix প্রয়োগ করার আগের চেয়ে *বড়* মার্জিনে — যা ঠিক সেই সংকেত, 9.4-এ আলোচিত, যা raw log ঘেঁটে দেখার তাগিদ দিল।

### 10.2 দ্বিতীয় চেষ্টা: Entropy-র Bug ঠিক করা

Entropy-restart mechanism (9.4) চিহ্নিত ও সংশোধন করার পর — cloning phase-এই entropy pressure নরম করে দিয়ে (যাতে অনুকরণটা তথ্যবহুল থাকে, কিন্তু একদম শক্ত না হয়ে যায়, যা পরবর্তী fine-tuning-এর সময় gradient ঠিকমতো প্রবাহিত হতেও সাহায্য করে), আর post-cloning exploration schedule-কে সর্বোচ্চে reset না করে একটা নিচু starting value থেকে শুরু হতে দিয়ে — result গুণগতভাবে বদলে গেল: **network constant-এর সাথে statistical parity অর্জন করল।** জয় নয়, কিন্তু আর কোনো লজ্জাজনক পরাজয়ও নয় — পার্থক্যটা ছোট ছিল, শূন্য থেকে statistically আলাদা করা যাচ্ছিল না। বাস্তবে, দুই policy প্রায় একই operating point-এ গিয়ে মিলল (তাদের realized error rate এক percent-এরও কম ব্যবধানে মিলে গেল), যা নিশ্চিত করে এটা কোনো গড়ের কাকতালীয় মিল নয়, বরং একই সমাধানের দিকে একটা সত্যিকারের একত্রীকরণ।

Parity-র চেয়েও তথ্যবহুল যেটা: অনুকরণটা ইতিমধ্যে জায়গায় বসানোর *পরে* যে আরও অনেক training করানো হলো, তাতে কোনো বাড়তি উন্নতি হলো না। যা কিছু সুযোগ বাকি ছিল — একটা পুরো training budget, সমৃদ্ধ state তথ্য, প্রকৃত gradient-based learning — সবকিছু হাতে পেয়েও, network constant-কে অনুকরণ করার চেয়ে বেশি কিছু যোগ করার মতো কিছুই খুঁজে পেল না। এটা শুধু parity-র সংখ্যার চেয়েও জোরালো প্রমাণ: এটা বলে দেয় ceiling-টা সত্যিই অর্জিত হয়েছে, নেহাত সৌভাগ্যক্রমে মিলে যায়নি।

### 10.3 একটা বাকি থাকা আপত্তি বন্ধ করা

এখানে থেমে যাওয়ার একটা স্পষ্ট, যুক্তিসঙ্গত আপত্তি আছে: parity অর্জন করা network-টাকে calibrated constant-এর উত্তর সরাসরি নকল করিয়ে initialize করা হয়েছিল। মিলবেই তো — তাকে উত্তরপত্রটাই দেখানো হয়েছে। এই আপত্তিটা গুরুত্ব সহকারে নিতে হবে, কারণ এটা এই দাবিকে দুর্বল করে দেয় যে reinforcement learning constant-এর জন্য প্রয়োজনীয় সেই একই calibration data *ছাড়াই* এই performance level-এ পৌঁছাতে পারে।

Fix হলো একটা পরিষ্কার control: একই সংশোধিত সেটআপ দিয়ে network-কে আবার train করা, কিন্তু behavior-cloning ধাপ *ছাড়াই* — একদম শূন্য থেকে, শুধু environment-এর সাথে নিজের trial-and-error interaction থেকে শিখে, constant-এর calibrated উত্তর একবারও না দেখিয়ে। এই version-ও near-parity অর্জন করল (একটা ছোট, statistically significant নয় এমন ফাঁক রয়ে গেল), সাথে সাথে OLLA-কে একটা জোরালো, significant মার্জিনে হারিয়েও। এটাই সেই version, যা প্রকৃতপক্ষে এই দাবিকে সমর্থন করে: "learned adaptation oracle-এর calibration pass ছাড়াই এই performance level-এ পৌঁছায়" — অনুকরণ থেকে শুরু করা version *অর্জনযোগ্য ceiling*-টা দেখায়; আর এই শূন্য-থেকে-শুরু করা version দেখায় যে সেই ceiling-এ *সততার সাথেই প্রায় পৌঁছানো যায়*।

---

## Part 11: একটা Adversarial Sanity Check, আর চূড়ান্ত Decisive Experiment

### 11.1 কেন ইচ্ছাকৃতভাবে দ্বিমত খোঁজা

Research project-এর এই বিন্দু পর্যন্ত, বেশ কয়েকটা স্বাধীনভাবে পাওয়া প্রমাণ একই দিকে ইঙ্গিত করছিল: constant network-এর সাথে মিলে যায়, আর যে refinement-ই প্রয়োগ করা হোক না কেন, network কখনো তাকে ছাড়িয়ে যায় না। একটা research project-এর ঠিক এই পর্যায়ে একটা পরিচিত ঝুঁকি থাকে — **confirmation bias**: একবার আপনার data ব্যাখ্যা করা একটা সংগতিপূর্ণ গল্প দাঁড়িয়ে গেলে, সেই *একই* data-র বিকল্প ব্যাখ্যা জোরালোভাবে খোঁজা বন্ধ করে দেওয়াটা সহজ হয়ে যায় — কারণ আপনি যা কিছু যাচাই করেন, তাই মনে হয় আপনার আগে থেকেই বিশ্বাস করা জিনিসটাকে সমর্থন করছে।

এখানে যে response নেওয়া হয়েছিল তা ছিল ইচ্ছাকৃতভাবে সংগঠিত, adversarial যাচাই খোঁজা — স্বাধীন reviewer-দের একটা দলকে স্পষ্টভাবে দায়িত্ব দেওয়া, reasoning-এ ভুল খুঁজে বের করার, শুধু "এটা কি ঠিক লাগছে?" জিজ্ঞেস করার বদলে। এতেই সামনে এলো এমন একটা আপত্তি, যা এতদিন অভ্যন্তরীণভাবে বিবেচনায়ই আসেনি।

### 11.2 আপত্তিটা

RL agent-এর operating point-এর error rate বেশ বেশি (প্রথম চেষ্টার প্রায় ৪০–৪৫% fail করে, HARQ retransmission বেশিরভাগটা উদ্ধার করার আগে) — OLLA-র প্রথাগত টার্গেট ১০%-এর চেয়ে অনেক বেশি error rate। Reviewer-দের উদ্বেগ ছিল: OLLA-র ওপর যে advantage মাপা হয়েছে, তা কি শুধু এই কারণেই, যে OLLA-র target কখনো নতুন পদার্থবিদ্যার জন্য re-tune করা হয়নি (নির্দিষ্টভাবে, Part 6.1-এ যোগ করা HARQ retransmission gain, যা প্রথম-চেষ্টায় বেশি error rate সহ্য করাটা আগের চেয়ে সস্তা করে তুলেছে)? আপনি যদি শুধু OLLA-র নিজের target error rate মেলানোর জন্য সেটাকে ওপরে সরিয়ে নেন, তাহলে কি OLLA নিজেই সেই ফাঁকটা বন্ধ করে দেবে, কোনো learning ছাড়াই?

এটা একটা গুরুতর আপত্তি: এটা সত্য হলে, "RL OLLA-কে হারায়" — এই finding-টা আসলে দাঁড়াবে "কেউ নতুন HARQ পদার্থবিদ্যার জন্য classical baseline re-tune করতেই ভুলে গিয়েছিল" — এমন একটা finding-এ, যা অনেক কম আকর্ষণীয়, আর প্রকৃতপক্ষে learning সম্পর্কেও কিছু বলে না।

### 11.3 কেন এটা টেস্ট করা সস্তা ছিল, আর টেস্ট কী দেখাল

গুরুত্বপূর্ণ কথা হলো, এই আপত্তিটা কিছু retrain না করেই টেস্ট করা যেত। OLLA-র target error rate নিছক algorithm-এর একটা fixed parameter, কোনো শেখা জিনিস নয় — তাই এটা কেবল কয়েকটা ভিন্ন target value-তে আবার চালিয়ে দেখা যায়, campaign জুড়ে আগে থেকেই ব্যবহৃত একই held-out test scenario-তে, আর (আগে থেকেই trained, অপরিবর্তিত) neural network-এর fixed operating point-এর সাথে তুলনা করা যায়। এতে ঘণ্টার পর ঘণ্টা retraining লাগে না, মাত্র কয়েক মিনিটের computation লাগে — যা এটাকে চালানোর জন্য অস্বাভাবিকভাবে উঁচু-মূল্যের একটা experiment করে তোলে: এটা সম্ভাব্যভাবে পুরো project-এর কেন্দ্রীয় finding-টাকেই উল্টে দিতে পারত, প্রায় বিনামূল্যে।

আরও দুটো control-সহ চালানো হলো, যা আরও দুটো সম্ভাব্য artifact-কে target করে: একটা policy, যে পুরোপুরি random action বেছে নেয় (বাদ দিতে যে "network noise থেকে আলাদা করা যায় না, এমন কিছুই শেখেনি"), আর একটা *ভিন্ন* একক constant, network-এর action range-এর গড়ের সাথে মিলিয়ে বেছে নেওয়া (যাচাই করতে network-এর advantage সত্যিই নিছক "সবসময় এক ধাপ বেশি গরম চালাও"-এর চেয়ে বেশি কিছু কি না)।

**Result:** OLLA-র target error rate একটা বিস্তৃত range জুড়ে re-tune করেও ফাঁকটা বন্ধ **হলো না** — টেস্ট করা প্রতিটা target জুড়েই OLLA সর্বোচ্চ যা করতে পারত, তা neural network-এর throughput-এর অনেক নিচেই থেকে গেল, উঁচু statistical significance-এ। Random-action control নিশ্চিত করল, network-এর আচরণ noise থেকে স্পষ্টভাবেই আলাদা। আর single-constant control, আগ্রহোদ্দীপকভাবে, দেখাল যে network-এর advantage একটা ভালোভাবে বেছে নেওয়া একক constant যা অর্জন করে, তার থেকে statistically আলাদা নয়।

একসাথে দেখলে, এই তিনটা result পরস্পরবিরোধী নয়, বরং সামঞ্জস্যপূর্ণ: OLLA-র ওপর network-এর advantage সত্যিকারের, আর এটাকে একটা mis-tuned baseline বলে উড়িয়ে দেওয়ার adversarial চেষ্টাটা টেকেনি — কিন্তু সেই advantage-টা একটা single scalar operating-point shift দিয়েই ভালোভাবে ব্যাখ্যা করা যায়, ঠিক সেই "setpoint effect, learned situational adaptivity নয়" — এই সিদ্ধান্তের দিকেই, Part 5 থেকে শুরু হওয়া এই পুরো investigation-টা এসে মিলছে।

---

## Part 12: বড় ছবি

### 12.1 বৈজ্ঞানিকভাবে আসলে কী শেখা গেল

প্রতিটা আলাদা সংখ্যা বাদ দিয়ে দেখলে, চূড়ান্ত finding-টার আকৃতি এরকম: একটা redesign করা environment জুড়ে — যা বিশেষভাবে তৈরি করা হয়েছিল state-conditional adaptivity গুরুত্বপূর্ণ হয়ে ওঠার *পরিস্থিতি* তৈরি করতে (costly error, ভিন্ন ভিন্ন user, আকস্মিক regime পরিবর্তন, বাস্তবসম্মত পদার্থবিদ্যা, আর একটা ন্যায্য information তুলনা) — একটা শেখা neural-network policy ধারাবাহিকভাবে পৌঁছে যায় সেরা সম্ভাব্য *অপরিবর্তনীয়* নিয়মের performance-এ, কিন্তু তাকে ছাড়িয়ে যায় না — এমনকি সেই নিয়মকে user কোন broad category-র, তার ওপর নির্ভর করতে দেওয়ার পরেও। তবে, এটা নির্ভরযোগ্যভাবে ও জোরালোভাবে classical reactive control algorithm-কে ছাড়িয়ে যায়, যা আজ প্রকৃত network-এ deploy করা হচ্ছে — আর সেই লাভটা একে measurement artifact বলে উড়িয়ে দেওয়ার প্রতিটা চেষ্টাতেই টিকে থাকে।

### 12.2 কেন এটা এখনো একটা প্রকৃত, কাজের Result

"চটকদার method সহজ baseline-কে হারাতে পারেনি" — এটাকে একটা ব্যর্থতা হিসেবে পড়ে ফেলাটা সহজ হতো। এখানে স্পষ্ট করে বলা দরকার, কেন সেই পাঠটা ভুল।

প্রথমত, **নিয়মমাফিকভাবে অর্জিত একটা negative result একটা নির্দিষ্ট, আগে থেকে খোলা থাকা scientific প্রশ্নকে বন্ধ করে দেয়** — "বাস্তবসম্মত এই পরিস্থিতিতে link adaptation-এ state-conditional adaptivity-র কি মাপযোগ্য কোনো মূল্য আছে?" — প্রকৃত প্রমাণ দিয়ে, শুধু একটা যাচাই-না-করা ধারণা হিসেবে ফেলে না রেখে। চারপাশের গবেষণাপত্রগুলোয় কতটা ঘন ঘন "RL OLLA-কে হারায়" দাবি করা হয়, Part 5-এ বর্ণিত constant-offset control না চালিয়েই — তা বিবেচনা করলে, এই result একটা সতর্কবার্তাও: সেই দাবিগুলোও হয়তো প্রায়ই একই setpoint effect-ই report করছে, শুধু একটা বেশি জমকালো নামে।

দ্বিতীয়ত, **যে প্রক্রিয়ার মাধ্যমে এটা প্রতিষ্ঠিত হয়েছে, সেটা নিজেই একটা টেমপ্লেট।** Pipeline বিশ্বাসযোগ্য হওয়ার আগে debugging-এর ছয়টা বড় version (Part 4); experiment চালানোর আগে success criterion pre-register করা (Part 7); বারবার চালিয়ে ভাগ্য পরীক্ষা করার বদলে code আর log পড়ে একটা বিস্ময়কর result diagnose করা (Part 9); একটা circularity আপত্তি বন্ধ করতে একটা from-scratch control চালানো (Part 10.3); অভ্যন্তরীণ ঐকমত্যে থেমে না গিয়ে ইচ্ছাকৃতভাবে adversarial review খোঁজা (Part 11.1); আর সিদ্ধান্তটাকে উল্টে দিতে পারে এমন সবচেয়ে সস্তা সম্ভাব্য experiment খুঁজে বের করে সেটা সত্যিই চালানো (Part 11.3) — এর প্রতিটাই, একটা শেখা method একটা classical method-কে হারায় বলে দাবি করা যেকোনো গবেষণার জন্যই একটা রক্ষণযোগ্য, অন্যত্র প্রয়োগযোগ্য চর্চা।

তৃতীয়ত, একটা প্রকৃত ইতিবাচক, ব্যবহারিক দাবি এখনো দাঁড়িয়ে আছে: একটা শেখা policy একটা oracle-calibrated নিয়মের performance-এ পৌঁছায়, *সেই oracle-এর calibration data ছাড়াই* — যার প্রকৃত deployment-মূল্য আছে (প্রতিটা deployment-এ আলাদা manual tuning-এর দরকার পড়ে না), যদিও এটা যত্ন করে করা manual tuning-এর তুলনায় কোনো throughput উন্নতি বোঝায় না।

### 12.3 কী এখনো খোলা রয়ে গেছে

এই investigation কিছু জিনিস সমাধান করেনি, আর সেগুলোকে সমাধান হয়ে গেছে বলে বেশি দাবি করা উচিত নয়: একটা ভিন্ন, আরও চরম ধরনের non-stationarity (feedback delay-র চেয়েও কম স্থায়িত্বের burst, যাতে reactive loop সত্যিই তাল মেলাতেই না পারে) কি finding-টা বদলে দিত; অন্য কোনো, এখনো পরীক্ষা না করা state feature কি অনুপস্থিত সংকেতটা বহন করতে পারত; আর from-scratch result-এর (Part 10.3) near-parity কি সত্যিই শূন্য ফাঁক, নাকি একটা ছোট ফাঁক যা আরও বড় একটা experiment বেশি statistical power দিয়ে মীমাংসা করে দিতে পারত। এগুলো স্বাভাবিক পরবর্তী প্রশ্ন, ঢেকে রাখার মতো আলগা সুতো নয়।

---

## Part 13: Glossary

- **BLER (Block Error Rate):** একটা নির্দিষ্ট MCS আর channel quality-র জন্য, পাঠানো একটা data block uncorrectable error নিয়ে receive হওয়ার probability।
- **CQI (Channel Quality Indicator):** receiver-এর পাঠানো একটা quantized report, channel quality (SINR) সম্পর্কে তার অনুমান সংক্ষেপ করে।
- **Coherence time:** যে time window-এর মধ্যে একটা wireless channel-কে প্রায় constant ধরা যায়; user speed বাড়ার সাথে সাথে কমে যায় (Doppler spread-এর মাধ্যমে)।
- **HARQ (Hybrid Automatic Repeat Request):** একটা retransmission protocol, যেখানে ব্যর্থ transmission ফেলে না দিয়ে retry করা হয়, আর আগেরটার সাথে মিলিয়ে নেওয়া হয় (chase combining) — শেষ পর্যন্ত সফল হওয়ার সম্ভাবনা বাড়িয়ে।
- **MCS (Modulation and Coding Scheme):** একটা transmission-এর জন্য বেছে নেওয়া modulation order আর code rate-এর নির্দিষ্ট মিশেল, data rate-কে error-এর বিরুদ্ধে সহনশীলতার সাথে trade off করে।
- **MDP / POMDP (Partially Observable Markov Decision Process):** reinforcement learning-এর underlying formal গাণিতিক মডেল — state, action, reward, আর (POMDP-র ক্ষেত্রে) প্রকৃত state সরাসরি দেখা যায় না, এই বাস্তবতা।
- **OLLA (Outer Loop Link Adaptation):** link adaptation-এর জন্য classical, industry-standard reactive control algorithm, গঠনগতভাবে একটা integral controller, ACK/NACK feedback দিয়ে চালিত।
- **Pre-registration:** একটা experiment চালানোর আগেই, ঠিক কী দিয়ে success গণ্য হবে তা লিখে রাখা — যাতে data দেখার পরে সুবিধাজনক metric, subset, বা পরিস্থিতি বেছে নেওয়া ঠেকানো যায়।
- **SINR (Signal-to-Interference-plus-Noise Ratio):** received signal power-এর সাথে interference আর noise-এর মিলিত power-এর অনুপাত; error-free data rate কতটা অর্জনযোগ্য, তার প্রধান নির্ধারক।
- **Setpoint effect:** একটা result, যেখানে আপাত "শেখা" advantage আসলে পুরোপুরি একটা fixed operating-point shift দিয়েই ব্যাখ্যা করা যায়, পরিস্থিতি অনুযায়ী বদলানো কোনো decision-making দিয়ে নয়।
- **TTI (Transmission Time Interval):** discrete সময়ের টুকরো (এখানে, ১ millisecond), যার মধ্যে scheduling আর transmission সিদ্ধান্ত নেওয়া হয়।
- **Waterfall curve:** একটা নির্দিষ্ট MCS-এর বৈশিষ্ট্যসূচক খাড়া BLER-বনাম-SINR curve।
- **Wilcoxon signed-rank test:** paired data-র জন্য একটা nonparametric statistical hypothesis test, এখানে ব্যবহৃত হয়েছে কারণ এটা ধরে নেয় না যে তুলনা করা রাশিগুলো normally distributed।

---

**এই গাইডটা দুটো technical report-এর একটা সহযোগী দলিল, বিকল্প নয়:** `v7_technical_process_report.pdf` (সম্পূর্ণ reasoning আর diagnostic chain, বেশি ঘন technical আকারে) আর `v7_comprehensive_evaluation_report.pdf` (formal result, statistics, আর figure)।
