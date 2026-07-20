---
layout: default
title: Chicane
---

<section class="hero" aria-labelledby="hero-title">
  <div class="hero__copy">
    <p class="eyebrow">iPhone + iPad <span aria-hidden="true">·</span> F1 + MotoGP</p>
    <h1 id="hero-title">Friendly podium picks, without the spreadsheet.</h1>
    <p class="hero__lede">Chicane keeps race-weekend picks simple: choose P1, P2, and P3, score exact finishes, and follow a season with family and friends.</p>
    <div class="hero__actions">
      <a class="button button--primary" href="{{ site.github_url }}">View on GitHub <span aria-hidden="true">↗</span></a>
      <a class="button button--quiet" href="#weekend-flow">See a race weekend</a>
    </div>
    <ul class="signal-list" aria-label="Project foundation">
      <li>SwiftUI</li>
      <li>iPhone + iPad</li>
      <li>Local-first</li>
      <li>iCloud optional</li>
    </ul>
  </div>

  <aside class="status-card" aria-labelledby="build-status-title">
    <div class="status-card__topline">
      <span class="status-pill"><span class="status-dot" aria-hidden="true"></span>{{ site.status_label }}</span>
      <span class="status-card__meta">Race weekend</span>
    </div>
    <div class="house-mark" aria-hidden="true">
      <span></span><span></span><span></span><span></span>
    </div>
    <p class="status-card__kicker">Current app</p>
    <h2 id="build-status-title">Pick the podium.<br>Let Chicane keep score.</h2>
    <dl class="status-list">
      <div><dt>Formula 1</dt><dd>Supported</dd></div>
      <div><dt>MotoGP</dt><dd>Supported</dd></div>
      <div><dt>Shared leagues</dt><dd>Optional</dd></div>
    </dl>
  </aside>
</section>

<section class="section" aria-labelledby="principles-title">
  <div class="section-heading">
    <p class="eyebrow">The whole bet</p>
    <h2 id="principles-title">Three places. Exact points. No arguments.</h2>
    <p>Chicane turns a friendly weekend bet into a clean, repeatable ritual—from the first prediction to the season standings.</p>
  </div>

  <div class="principle-grid">
    <article class="principle-card">
      <span class="card-number" aria-hidden="true">01</span>
      <h3>Pick the podium</h3>
      <p>Each player chooses P1, P2, and P3 for Formula 1 or MotoGP, plus an optional season champion.</p>
    </article>
    <article class="principle-card">
      <span class="card-number" aria-hidden="true">02</span>
      <h3>Lock official results</h3>
      <p>Fetch the real top three, review them, and lock the event so the outcome stays settled.</p>
    </article>
    <article class="principle-card">
      <span class="card-number" aria-hidden="true">03</span>
      <h3>Watch standings move</h3>
      <p>Correct position means one point. Chicane totals each series and the combined season automatically.</p>
    </article>
  </div>
</section>

<section class="section section--split" id="weekend-flow" aria-labelledby="weekend-title">
  <article class="resident-card">
    <div class="resident-card__header">
      <div class="resident-icon" aria-hidden="true">
        <span></span><span></span><span></span>
      </div>
      <div>
        <p class="eyebrow">Weekend view</p>
        <h2 id="weekend-title">Everything before lights out</h2>
      </div>
    </div>
    <p class="resident-card__summary">The next race, track-local time, season snapshot, current picks, and each player’s bet stay together in one useful view.</p>
    <div class="boundary-note">
      <strong>Two series, one rhythm</strong>
      <span>Formula 1 · MotoGP · Individual player drafts</span>
    </div>
    <ul class="capability-list">
      <li><span aria-hidden="true">✓</span> Race countdown with track-local context</li>
      <li><span aria-hidden="true">✓</span> Independent picks for every player</li>
      <li><span aria-hidden="true">✓</span> Series and combined standings</li>
      <li><span aria-hidden="true">✓</span> Bundled data when the network is unavailable</li>
    </ul>
  </article>

  <div class="run-flow" aria-labelledby="flow-title">
    <p class="eyebrow">One race weekend</p>
    <h2 id="flow-title">From prediction to points.</h2>
    <ol>
      <li><span>01</span><div><strong>Open Weekend</strong><p>See what is coming next.</p></div></li>
      <li><span>02</span><div><strong>Choose a player</strong><p>Every person keeps a separate draft.</p></div></li>
      <li><span>03</span><div><strong>Pick P1, P2, P3</strong><p>Set the podium in exact order.</p></div></li>
      <li><span>04</span><div><strong>Fetch results</strong><p>Bring in the official top three.</p></div></li>
      <li><span>05</span><div><strong>Lock the event</strong><p>Freeze the confirmed outcome.</p></div></li>
      <li><span>06</span><div><strong>Count the season</strong><p>Standings update deterministically.</p></div></li>
    </ol>
  </div>
</section>

<section class="section foundation" aria-labelledby="foundation-title">
  <div>
    <p class="eyebrow">Local first. Shared when you want it.</p>
    <h2 id="foundation-title">Your season still works when the signal does not.</h2>
  </div>
  <p>Picks and results save on-device first with atomic local storage and bundled fallback data. Add a league code when the group wants iCloud sync across phones; leave it off for a completely local season.</p>
</section>
