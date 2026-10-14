(() => {
    'use strict';

    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'statewide_security';
    const $ = (sel, root = document) => root.querySelector(sel);
    const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
    // Lua encodes empty tables as {} - normalise anything that should be a list
    const arr = (v) => (Array.isArray(v) ? v : []);
    const money = (n) => '$' + Number(n || 0).toLocaleString();
    const duration = (s) => {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m ${s % 60}s`;
    };
    const clock = (t) => new Date(t * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    async function post(name, data = {}) {
        try {
            const res = await fetch(`https://${resource}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (e) {
            return null;
        }
    }

    // ------------------------------------------------------------------ toasts / radio
    function toast(text, kind = 'info') {
        const el = document.createElement('div');
        el.className = `toast ${kind}`;
        el.textContent = text;
        $('#toasts').appendChild(el);
        setTimeout(() => el.classList.add('out'), 5200);
        setTimeout(() => el.remove(), 5700);
    }

    function radio(from, text) {
        const feed = $('#radio-feed');
        const el = document.createElement('div');
        el.className = `radio-msg ${String(from).replace(/[^A-Z]/gi, '')}`;
        el.innerHTML = `<div class="from">${esc(from)}</div><div>${esc(text)}</div>`;
        feed.appendChild(el);
        while (feed.children.length > 5) feed.firstChild.remove();
        setTimeout(() => el.classList.add('out'), 11000);
        setTimeout(() => el.remove(), 11600);
    }

    function reward({ pay, xp, reason }) {
        if (!pay && !xp) return;
        const el = document.createElement('div');
        el.className = 'reward';
        el.innerHTML = `${pay ? `<span class="pay">+${money(pay)}</span>` : ''}` +
            `${xp ? `<span class="xp ${xp < 0 ? 'neg' : ''}">${xp > 0 ? '+' : ''}${xp} XP</span>` : ''}${esc(reason)}`;
        $('#rewards').appendChild(el);
        setTimeout(() => el.remove(), 2900);
    }

    // ------------------------------------------------------------------ HUD
    function hud(d) {
        $('#hud').classList.toggle('hidden', !d.show);
        if (!d.show) { $('#hud-patrol').classList.add('hidden'); return; }
        $('#hud-callsign').textContent = d.callsign || '';
        $('#hud-rank').textContent = d.rank || '';
    }

    function patrol(d) {
        if (d.clear) { $('#hud-patrol').classList.add('hidden'); return; }
        $('#hud-patrol').classList.remove('hidden');
        $('#hud-site').textContent = `${d.site} · Lap ${d.lap}`;
        $('#hud-progress-fill').style.width = `${((d.index - 1) / d.total) * 100}%`;
        $('#hud-next').textContent = `Next checkpoint ${d.index}/${d.total}: ${d.next}`;
    }

    let objectiveTimer;
    function objective(d) {
        const el = $('#objective');
        clearTimeout(objectiveTimer);
        if (d.clear) { el.classList.add('hidden'); return; }
        el.textContent = d.text;
        el.classList.remove('hidden');
        objectiveTimer = setTimeout(() => el.classList.add('hidden'), 12000);
    }

    let alertTimer;
    function incidentAlert(d) {
        const el = $('#incident-alert');
        el.className = d.priority >= 3 ? 'p3' : '';
        el.innerHTML = `<div class="ia-tag">${d.priority >= 3 ? 'PRIORITY INCIDENT' : 'INCIDENT'}</div>
            <div class="ia-title">${esc(d.label)}</div><div class="ia-loc">${esc(d.location)} · GPS route set</div>`;
        clearTimeout(alertTimer);
        alertTimer = setTimeout(() => el.classList.add('hidden'), 7000);
    }

    let progressAnim;
    function progress(d) {
        const wrap = $('#progress'), fill = $('#progress-fill');
        cancelAnimationFrame(progressAnim);
        if (d.cancel) { wrap.classList.add('hidden'); return; }
        $('#progress-label').textContent = d.label;
        wrap.classList.remove('hidden');
        const start = performance.now();
        const tick = (now) => {
            const pct = Math.min(1, (now - start) / d.duration);
            fill.style.width = `${pct * 100}%`;
            if (pct < 1) progressAnim = requestAnimationFrame(tick);
            else setTimeout(() => wrap.classList.add('hidden'), 150);
        };
        progressAnim = requestAnimationFrame(tick);
    }

    let radioCheckTimer;
    function radioCheck(d) {
        const el = $('#radio-check');
        clearInterval(radioCheckTimer);
        if (d.clear) { el.classList.add('hidden'); return; }
        let left = d.window;
        const render = () => {
            el.innerHTML = `<b>RADIO CHECK</b> · press <b>${esc(d.key)}</b> or type <b>/10-4</b> · ${left}s`;
        };
        render();
        el.classList.remove('hidden');
        radioCheckTimer = setInterval(() => {
            left -= 1;
            if (left <= 0) { clearInterval(radioCheckTimer); el.classList.add('hidden'); return; }
            render();
        }, 1000);
    }

    function panic(d) {
        const el = $('#panic-flash');
        el.classList.remove('hidden');
        setTimeout(() => el.classList.add('hidden'), 3800);
        toast(d.own ? 'Panic alarm sent. Units and LSPD responding.' : `PANIC ALARM: ${d.callsign} needs assistance!`, 'error');
    }

    let resultTimer;
    function incidentResult({ label, result }) {
        const el = $('#result-card');
        const r = result;
        const color = r.rating >= 75 ? 'c-green' : r.rating >= 45 ? 'c-yellow' : 'c-red';
        el.innerHTML = `<h3>INCIDENT CLOSED</h3>
            <div class="rc-title">${esc(label)} — ${esc(r.outcomeLabel)}</div>
            <div class="rc-rating"><span class="num ${color}">${r.rating}%</span><span class="lbl">handling rating</span></div>
            ${r.complaint ? `<div class="rc-line bad">Complaint filed: ${esc(r.complaint)}</div>` : ''}
            ${arr(r.notes).map((n) => `<div class="rc-line">• ${esc(n)}</div>`).join('')}
            <div class="rc-reward"><span class="c-green">+${money(r.pay)}</span> · <span class="${r.xp < 0 ? 'c-red' : ''}">${r.xp > 0 ? '+' : ''}${r.xp} XP</span></div>
            <div class="rc-hint">Open your tablet to file the incident report.</div>`;
        el.classList.remove('hidden');
        clearTimeout(resultTimer);
        resultTimer = setTimeout(() => el.classList.add('hidden'), 12000);
    }

    // ------------------------------------------------------------------ generic menu
    let menuId = null;
    function openMenu(d) {
        menuId = d.id;
        $('#menu-title').textContent = d.title;
        $('#menu-subtitle').textContent = d.subtitle || '';
        const list = $('#menu-items');
        list.innerHTML = '';
        arr(d.items).forEach((item) => {
            const b = document.createElement('button');
            b.className = 'menu-item';
            b.disabled = !!item.disabled;
            b.innerHTML = `${esc(item.label)}${item.desc ? `<small>${esc(item.desc)}</small>` : ''}`;
            b.addEventListener('click', () => closeMenu(item.value));
            list.appendChild(b);
        });
        $('#menu').classList.remove('hidden');
    }
    function closeMenu(value = null) {
        if (menuId === null) return;
        $('#menu').classList.add('hidden');
        post('menuSelect', { id: menuId, value });
        menuId = null;
    }

    // ------------------------------------------------------------------ interaction dialog
    let dialogId = null;
    function dialogRender(d) {
        dialogId = d.id;
        $('#dlg-type').textContent = `${d.label} · ${d.location}`;
        $('#dlg-subject').textContent = d.subject;
        $('#dlg-meta').textContent = d.dob ? `DOB ${d.dob} · ${d.idNumber}` : 'Not identified';
        const dem = $('#dlg-demeanor');
        dem.textContent = d.demeanor;
        dem.className = `c-${d.demeanorColor}`;
        $('#dlg-coop').textContent = d.cooperation;
        const rec = $('#dlg-records');
        if (d.idStatus === 'warrant') { rec.textContent = 'WARRANT'; rec.className = 'c-red'; }
        else if (d.idStatus === 'clear') { rec.textContent = 'Clear'; rec.className = 'c-green'; }
        else if (d.idStatus === 'unknown') { rec.textContent = 'No record'; rec.className = 'c-orange'; }
        else { rec.textContent = 'Not checked'; rec.className = 'c-grey'; }

        const flags = [];
        if (d.warrant) flags.push(`<span class="flag bad">Warrant: ${esc(d.warrant)}</span>`);
        if (arr(d.contraband).length) flags.push(`<span class="flag bad">Found: ${esc(arr(d.contraband).join(', '))}</span>`);
        else if (d.contraband) flags.push('<span class="flag good">Search: nothing found</span>');
        if (d.state === 'detained' || d.state === 'escorted') flags.push('<span class="flag">Handcuffed</span>');
        if (d.state === 'subdued') flags.push('<span class="flag">Subdued</span>');
        if (d.policeCalled) flags.push('<span class="flag">LSPD en route</span>');
        if (d.emsCalled) flags.push('<span class="flag">EMS en route</span>');
        $('#dlg-flags').innerHTML = flags.join('');

        const actions = $('#dlg-actions');
        actions.classList.remove('busy');
        actions.innerHTML = '';
        arr(d.actions).forEach((a) => {
            const b = document.createElement('button');
            b.className = `act ${a.tone}`;
            b.textContent = a.label;
            b.addEventListener('click', () => {
                actions.classList.add('busy');
                post('dialogAction', { id: dialogId, action: a.id });
            });
            actions.appendChild(b);
        });
    }
    function dialogLine(d) {
        if (d.id !== dialogId) return;
        const t = $('#dlg-transcript');
        const el = document.createElement('div');
        el.className = `line ${d.who}`;
        el.textContent = d.text;
        t.appendChild(el);
        t.scrollTop = t.scrollHeight;
    }
    function dialog(d) {
        if (!d.open) { $('#dialog').classList.add('hidden'); dialogId = null; return; }
        if (dialogId !== d.data.id) $('#dlg-transcript').innerHTML = '';
        dialogRender(d.data);
        $('#dialog').classList.remove('hidden');
    }

    // ------------------------------------------------------------------ shift summary
    function shiftSummary(s) {
        const items = [
            ['Shift length', duration(s.duration)], ['Earned', money(s.pay)],
            ['XP', `${s.xp >= 0 ? '+' : ''}${s.xp}`], ['Checkpoints', s.checkpoints],
            ['Routes', s.routes], ['Incidents', s.incidents], ['Radio checks', s.radioChecks],
        ];
        $('#summary-body').innerHTML = items.map(([k, v]) =>
            `<div class="card stat"><div class="k">${esc(k)}</div><div class="v">${esc(v)}</div></div>`).join('');
        $('#summary').classList.remove('hidden');
    }

    // ------------------------------------------------------------------ tablet
    let data = null;
    let reportScope = 'unreviewed';

    function setTab(tab) {
        $$('#tabs button').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
        $$('.panel').forEach((p) => p.classList.toggle('active', p.dataset.panel === tab));
        if (tab === 'reports') renderReports();
        if (tab === 'review') renderReview();
    }

    function renderOverview() {
        const p = data.profile, s = data.shift;
        const span = p.nextRankXp ? p.nextRankXp - p.rankXp : 1;
        const pct = p.nextRankXp ? Math.min(100, ((p.xp - p.rankXp) / span) * 100) : 100;

        const shiftStats = s ? [
            ['On shift', duration(s.elapsed)], ['Shift pay', money(s.pay)], ['Shift XP', s.xp],
            ['Checkpoints', s.checkpoints], ['Routes', s.routes], ['Incidents', s.incidents],
            ['Radio checks', s.radioChecks], ['Status', s.status],
        ] : null;

        const career = [
            ['Shifts', p.shifts], ['Lifetime earnings', money(p.earnings)], ['Incidents', p.stats.incidents],
            ['Arrests', p.stats.arrests], ['Assists', p.stats.assists], ['Reports filed', p.stats.reports],
            ['Commendations', p.stats.commendations], ['Complaints', p.stats.complaints],
        ];
        const stat = ([k, v]) => `<div class="card stat"><div class="k">${esc(k)}</div><div class="v">${esc(v)}</div></div>`;

        $('[data-panel="overview"]').innerHTML = `
            <h2>Welcome, ${esc(p.callsign)}</h2>
            <div class="sub">${esc(p.name)} · ${data.onDuty ? 'On duty' : 'Off duty'}</div>
            <div class="card rank-card">
                <div class="rank-badge">${p.rankIndex}</div>
                <div class="rank-info">
                    <div class="rank-name">${esc(p.rank)}</div>
                    <div class="rank-xp">${p.xp} XP${p.nextRank ? ` · ${p.nextRankXp - p.xp} XP to ${esc(p.nextRank)}` : ' · Top rank'}</div>
                    <div class="bar"><div style="width:${pct}%"></div></div>
                    <div class="ladder">${arr(data.ranks).map((r, i) =>
                        `<div class="${p.xp >= r.xp ? 'reached' : ''} ${r.current ? 'current' : ''}">${esc(r.name)}<br>${r.xp} XP</div>`).join('')}</div>
                </div>
            </div>
            ${s ? `
                <h3>Current shift${s.site ? ` · ${esc(s.site)}` : ''}</h3>
                ${s.patrol ? `<div class="card" style="margin-bottom:12px">Patrol lap ${s.patrol.lap} · checkpoint ${s.patrol.index}/${s.patrol.total} · next: <b>${esc(s.patrol.next)}</b></div>` : ''}
                <div class="grid cols-4">${shiftStats.map(stat).join('')}</div>
                <h3>Shift log</h3>
                <div class="log">${arr(s.log).length ? arr(s.log).map((l) => `<div><time>${clock(l.t)}</time>${esc(l.text)}</div>`).join('') : '<div>No activity yet.</div>'}</div>
            ` : `<h3>Getting started</h3>
                <div class="card">Head to <b>HQ</b> and clock on at the duty point. Grab a vehicle from the motor pool, pick a site in the <b>Sites</b> tab, then speak to the site contact to start your patrol.
                <div class="row" style="margin-top:10px"><button class="btn primary" data-gps="hq">Set GPS to HQ</button></div></div>`}
            <h3>Career</h3>
            <div class="grid cols-4">${career.map(stat).join('')}</div>`;
    }

    function renderSites() {
        $('[data-panel="sites"]').innerHTML = `
            <h2>Sites</h2>
            <div class="sub">Contracts available to ${esc(data.company)}. Higher-risk sites pay more and unlock with rank.</div>
            <div class="grid cols-2">${arr(data.sites).map((s) => `
                <div class="card site-card ${s.locked ? 'locked' : ''} ${s.active ? 'active' : ''}">
                    <div class="site-head">
                        <div class="site-title">${esc(s.label)}</div>
                        ${s.active ? '<span class="tag good">Assigned</span>' : s.locked ? `<span class="tag bad">${esc(s.minRankName)}+</span>` : '<span class="tag accent">Open</span>'}
                    </div>
                    <div class="site-brief">${esc(s.briefing)}</div>
                    <div class="site-foot">
                        <div class="row"><span class="tag">${s.checkpoints} checkpoints</span><span class="tag">Pay ×${Number(s.payMult).toFixed(2)}</span></div>
                        <button class="btn ${s.locked ? '' : 'primary'}" data-gps="${esc(s.id)}" ${s.locked ? 'disabled' : ''}>Set GPS</button>
                    </div>
                </div>`).join('')}
            </div>`;
    }

    function renderTeam() {
        const team = arr(data.team);
        $('[data-panel="team"]').innerHTML = `
            <h2>Team</h2>
            <div class="sub">${team.length} guard${team.length === 1 ? '' : 's'} on duty</div>
            ${!data.onDuty ? '<div class="empty">Clock on to see who is on shift.</div>' : `
            <div class="card" style="padding:0">
                <table><thead><tr><th>Callsign</th><th>Name</th><th>Rank</th><th>Site</th><th>Status</th></tr></thead>
                <tbody>${team.map((g) => `<tr><td><b>${esc(g.callsign)}</b></td><td>${esc(g.name)}</td><td>${esc(g.rank)}</td>
                    <td>${esc(g.site || '—')}</td><td class="status-${esc(g.status)}">${esc(g.status)}</td></tr>`).join('')}</tbody></table>
            </div>`}`;
    }

    function gradeClass(g) { return g >= 75 ? 'g-good' : g >= 45 ? 'g-mid' : 'g-bad'; }

    function reportDetail(r, withReview) {
        return `
            <div class="stack">
                <div class="notes">Filed ${esc(r.filed)} by <b>${esc(r.callsign)}</b> (${esc(r.authorRank)}) · ${esc(r.site)} – ${esc(r.location)}</div>
                <div class="notes">Category: <b>${esc(r.category)}</b> · Outcome: <b>${esc(r.outcome)}</b>${r.subjectName ? ` · Subject: <b>${esc(r.subjectName)}</b>` : ''}</div>
                <div class="narrative">${esc(r.narrative)}</div>
                ${arr(r.contraband).length ? `<div class="notes">Evidence: ${esc(arr(r.contraband).join(', '))}</div>` : ''}
                <div class="timeline">${esc(arr(r.timeline).join('\n'))}</div>
                ${r.complaint ? `<div class="rc-line bad">Complaint: ${esc(r.complaint)}</div>` : ''}
                ${arr(r.systemNotes).length ? `<ul class="notes">${arr(r.systemNotes).map((n) => `<li>${esc(n)}</li>`).join('')}</ul>` : ''}
                ${arr(r.feedback).length ? `<ul class="notes">${arr(r.feedback).map((n) => `<li>${esc(n)}</li>`).join('')}</ul>` : ''}
                ${r.review ? `<div class="card"><b>${esc(r.review.verdict.toUpperCase())}</b> by ${esc(r.review.by)} · ${esc(r.review.at)}${r.review.comment ? `<div class="notes" style="margin-top:4px">${esc(r.review.comment)}</div>` : ''}</div>` : ''}
                ${withReview && !r.review ? `
                    <div class="form">
                        <label>Supervisor comment<textarea data-review-comment="${r.id}" style="min-height:70px" maxlength="500"></textarea></label>
                        <div class="row end">
                            <button class="btn bad" data-review="${r.id}" data-verdict="returned">Return</button>
                            <button class="btn" data-review="${r.id}" data-verdict="approved">Approve</button>
                            <button class="btn good" data-review="${r.id}" data-verdict="commended">Commend</button>
                        </div>
                    </div>` : ''}
            </div>`;
    }

    function reportSummaryRow(r) {
        const status = r.review ? r.review.verdict : 'Awaiting review';
        return `<details class="card">
            <summary class="report-row">
                <div><div class="rr-title">#${r.id} · ${esc(r.typeLabel)}</div>
                <div class="rr-meta">${esc(r.callsign)} · ${esc(r.site)} · ${esc(r.filed)} · ${esc(status)}</div></div>
                <div class="grade ${gradeClass(r.grade)}">${r.grade}%</div>
            </summary>
            ${reportDetail(r, false)}
        </details>`;
    }

    async function renderReports() {
        const panel = $('[data-panel="reports"]');
        const pending = arr(data.pendingReports);
        panel.innerHTML = `
            <h2>Incident Reports</h2>
            <div class="sub">Every closed incident needs a report. Accurate category, outcome, subject name and a detailed narrative earn full credit.</div>
            <h3>Pending (${pending.length})</h3>
            <div class="stack">${pending.length ? pending.map((p) => `
                <div class="card report-row">
                    <div><div class="rr-title">${esc(p.typeLabel)} · ${esc(p.location)}</div>
                    <div class="rr-meta">${esc(p.site)} · ${clock(p.time)} · ${p.complaint ? '<span class="c-red">complaint attached</span>' : 'no complaints'}</div></div>
                    <button class="btn primary" data-write="${p.incidentId}">Write report</button>
                </div>`).join('') : '<div class="empty">No reports waiting. Nice.</div>'}</div>
            <div id="report-form"></div>
            <h3>My filed reports</h3>
            <div class="stack" id="my-reports"><div class="empty">Loading…</div></div>`;
        const mine = arr(await post('reports', { scope: 'mine' }));
        const box = $('#my-reports');
        if (box) box.innerHTML = mine.length ? mine.map(reportSummaryRow).join('') : '<div class="empty">You have not filed any reports yet.</div>';
    }

    function openReportForm(incidentId) {
        const p = arr(data.pendingReports).find((x) => String(x.incidentId) === String(incidentId));
        if (!p) return;
        const form = $('#report-form');
        form.innerHTML = `
            <h3>Report · ${esc(p.typeLabel)} #${p.incidentId}</h3>
            <div class="card form">
                <div class="grid cols-2">
                    <label>Category<select id="rf-category">
                        <option value="">Select…</option>
                        ${arr(data.categories).map((c) => `<option>${esc(c)}</option>`).join('')}
                    </select></label>
                    <label>Outcome<select id="rf-outcome">
                        <option value="">Select…</option>
                        ${arr(data.outcomes).map((o) => `<option value="${esc(o.id)}">${esc(o.label)}</option>`).join('')}
                    </select></label>
                </div>
                <label>Subject name (if identified)<input id="rf-subject" maxlength="60" placeholder="Leave blank if not identified"></label>
                <label>Incident timeline (auto-recorded)<div class="timeline">${esc(arr(p.timeline).join('\n'))}</div></label>
                ${arr(p.contraband).length ? `<div class="notes">Evidence recovered: ${esc(arr(p.contraband).join(', '))}</div>` : ''}
                <label>Narrative<textarea id="rf-narrative" maxlength="2000" placeholder="Describe what you observed, the actions you took and why, and how the incident ended."></textarea>
                    <span class="counter" id="rf-count">0 / 160 recommended</span></label>
                <div class="row end"><button class="btn ghost" data-cancel-report>Cancel</button><button class="btn primary" data-submit-report="${p.incidentId}">Submit report</button></div>
            </div>`;
        $('#rf-narrative').addEventListener('input', (e) => {
            $('#rf-count').textContent = `${e.target.value.length} / 160 recommended`;
        });
        form.scrollIntoView({ behavior: 'smooth' });
    }

    async function submitReport(incidentId) {
        const report = {
            category: $('#rf-category').value,
            outcome: $('#rf-outcome').value,
            subjectName: $('#rf-subject').value.trim(),
            narrative: $('#rf-narrative').value.trim(),
        };
        if (!report.category || !report.outcome) { toast('Pick a category and outcome.', 'error'); return; }
        if (report.narrative.length < 20) { toast('Write a narrative first.', 'error'); return; }
        const res = await post('submitReport', { incidentId, report });
        if (!res || !res.ok) { toast((res && res.msg) || 'Submission failed.', 'error'); return; }
        toast(`Report #${res.id} filed · graded ${res.grade}%`, res.grade >= 60 ? 'success' : 'info');
        arr(res.feedback).forEach((f) => toast(f, 'info'));
        await refresh();
        setTab('reports');
    }

    async function renderReview() {
        const panel = $('[data-panel="review"]');
        panel.innerHTML = `
            <h2>Supervisor Review</h2>
            <div class="sub">Approve, commend or return reports. Commendations award the guard bonus XP; returned reports cost them XP.</div>
            <div class="seg"><button data-scope="unreviewed" class="${reportScope === 'unreviewed' ? 'active' : ''}">Awaiting review</button>
            <button data-scope="all" class="${reportScope === 'all' ? 'active' : ''}">All reports</button></div>
            <div class="stack" id="review-list"><div class="empty">Loading…</div></div>`;
        const list = arr(await post('reports', { scope: reportScope }));
        const box = $('#review-list');
        if (!box) return;
        box.innerHTML = list.length ? list.map((r) => `<details class="card">
            <summary class="report-row">
                <div><div class="rr-title">#${r.id} · ${esc(r.typeLabel)} · ${esc(r.callsign)}</div>
                <div class="rr-meta">${esc(r.site)} · ${esc(r.filed)} · ${r.review ? esc(r.review.verdict) : 'Awaiting review'}${r.complaint ? ' · <span class="c-red">complaint</span>' : ''}</div></div>
                <div class="grade ${gradeClass(r.grade)}">${r.grade}%</div>
            </summary>
            ${reportDetail(r, true)}
        </details>`).join('') : '<div class="empty">Nothing to review.</div>';
    }

    async function review(id, verdict) {
        const comment = ($(`[data-review-comment="${id}"]`) || {}).value || '';
        const res = await post('reviewReport', { id, verdict, comment });
        if (!res || !res.ok) { toast((res && res.msg) || 'Review failed.', 'error'); return; }
        toast(`Report #${id} ${verdict}.`, 'success');
        renderReview();
    }

    function renderTablet() {
        $('#brand-name').textContent = data.company;
        const status = $('#nav-status');
        status.textContent = data.onDuty ? 'On duty' : 'Off duty';
        status.classList.toggle('on', data.onDuty);
        const count = arr(data.pendingReports).length;
        const pill = $('#pending-count');
        pill.textContent = count;
        pill.classList.toggle('hidden', count === 0);
        $('#review-tab').classList.toggle('hidden', !data.profile.supervisor);
        renderOverview();
        renderSites();
        renderTeam();
    }

    async function refresh() {
        const fresh = await post('refresh');
        if (fresh && fresh.profile) { data = fresh; renderTablet(); }
    }

    function openTablet(d) {
        data = d.data;
        renderTablet();
        $('#tablet').classList.remove('hidden');
        setTab(d.tab || 'overview');
    }

    function closeTablet() {
        $('#tablet').classList.add('hidden');
        post('close');
    }

    // ------------------------------------------------------------------ events
    document.addEventListener('click', (e) => {
        const t = e.target.closest('button');
        if (!t) return;
        if (t.dataset.tab) setTab(t.dataset.tab);
        else if (t.dataset.close === 'tablet') closeTablet();
        else if (t.dataset.close === 'dialog') { $('#dialog').classList.add('hidden'); dialogId = null; post('dialogClose'); }
        else if (t.dataset.close === 'summary') { $('#summary').classList.add('hidden'); post('close'); }
        else if (t.dataset.gps) { post('setWaypoint', { siteId: t.dataset.gps }); }
        else if (t.dataset.write) openReportForm(t.dataset.write);
        else if (t.hasAttribute('data-cancel-report')) $('#report-form').innerHTML = '';
        else if (t.dataset.submitReport) submitReport(Number(t.dataset.submitReport));
        else if (t.dataset.review) review(Number(t.dataset.review), t.dataset.verdict);
        else if (t.dataset.scope) { reportScope = t.dataset.scope; renderReview(); }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (menuId !== null) closeMenu(null);
        else if (!$('#dialog').classList.contains('hidden')) { $('#dialog').classList.add('hidden'); dialogId = null; post('dialogClose'); }
        else if (!$('#summary').classList.contains('hidden')) { $('#summary').classList.add('hidden'); post('close'); }
        else if (!$('#tablet').classList.contains('hidden')) closeTablet();
    });

    const handlers = {
        notify: (d) => toast(d.text, d.kind),
        radio: (d) => radio(d.from, d.text),
        reward,
        hud,
        patrol,
        objective,
        incidentAlert: (d) => { $('#incident-alert').classList.remove('hidden'); incidentAlert(d); },
        progress,
        radioCheck,
        panic,
        incidentResult,
        menu: openMenu,
        dialog,
        dialogUpdate: (d) => { if (d.data.id === dialogId) dialogRender(d.data); },
        dialogLine,
        shiftSummary: (d) => shiftSummary(d.summary),
        tablet: openTablet,
    };

    window.addEventListener('message', (e) => {
        const d = e.data;
        if (!d || !handlers[d.action]) return;
        handlers[d.action](d);
    });
})();
