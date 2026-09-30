var params = JSON.parse(value);

var t0 = Date.now();
var baseUrl = (params.base_url || 'https://api.wacm.wasabisys.com').replace(/\/+$/, '');
var user = params.username || '';
var key = params.api_key || '';
var maxAccounts = parseInt(params.max_accounts || '50', 10);
var includeDeleted = String(params.include_deleted || 'false') === 'true';
var statusFilter = String(params.status_filter || '').toUpperCase();

if (user === '' || user.indexOf('{$') === 0) {
    throw 'WACM username is not set - fill the {$WASABI.WACM.USER} macro. '
        + 'It is your WACM login, not the name of the API key.';
}
if (key === '' || key.indexOf('{$') === 0) {
    throw 'WACM API key is not set - fill the {$WASABI.WACM.KEY} macro.';
}

// ---- base64 (le moteur JS de Zabbix n'expose pas btoa de facon fiable)
var B64CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function base64(str) {
    var out = '', i = 0, c1, c2, c3, e1, e2, e3, e4;

    while (i < str.length) {
        c1 = str.charCodeAt(i++);
        c2 = str.charCodeAt(i++);
        c3 = str.charCodeAt(i++);

        e1 = c1 >> 2;
        e2 = ((c1 & 3) << 4) | (c2 >> 4);
        e3 = ((c2 & 15) << 2) | (c3 >> 6);
        e4 = c3 & 63;

        if (isNaN(c2)) {
            e3 = 64;
            e4 = 64;
        }
        else if (isNaN(c3)) {
            e4 = 64;
        }

        out += B64CHARS.charAt(e1) + B64CHARS.charAt(e2)
            + (e3 === 64 ? '=' : B64CHARS.charAt(e3))
            + (e4 === 64 ? '=' : B64CHARS.charAt(e4));
    }
    return out;
}

var authHeader = 'Authorization: Basic ' + base64(user + ':' + key);

function apiGet(path) {
    var req = new HttpRequest();

    if (params.proxy) {
        req.setHttpProxy(params.proxy);
    }
    req.addHeader(authHeader);
    req.addHeader('Accept: application/json');

    var body = req.get(baseUrl + path);
    var status = req.getStatus();

    if (status === 401) {
        throw 'HTTP 401 on ' + path + '. Check {$WASABI.WACM.USER}: it must be the '
            + 'WACM login (or the account name for an account key), not the key name.';
    }
    if (status === 403) {
        throw 'HTTP 403 on ' + path + '. The key is valid but lacks rights on this resource.';
    }
    if (status === 404) {
        return null;
    }
    if (status < 200 || status >= 300) {
        throw 'Request to ' + path + ' failed: HTTP ' + status + ' '
            + String(body).substring(0, 200);
    }
    try {
        return JSON.parse(body);
    }
    catch (e) {
        throw 'Cannot parse JSON response from ' + path;
    }
}

// Toutes les reponses ont la forme
//   { success, code, message, data: { items: [...], page, size, total }, errors }
function items(resp) {
    if (!resp || !resp.data) {
        return [];
    }
    if (resp.data.items) {
        return resp.data.items;
    }
    return [];
}

function totalOf(resp, fallback) {
    if (resp && resp.data && typeof resp.data.total === 'number') {
        return resp.data.total;
    }
    return fallback;
}

function num(v) {
    return (typeof v === 'number' && !isNaN(v)) ? v : null;
}

function toEpoch(s) {
    if (!s) {
        return null;
    }
    var t = Date.parse(s);
    return isNaN(t) ? null : Math.floor(t / 1000);
}

var now = Math.floor(Date.now() / 1000);
var out = {
    accounts: {},
    buckets: {},
    discovery_accounts: [],
    discovery_buckets: [],
    account_count: 0,
    bucket_count: 0,
    accounts_total: 0,
    accounts_eligible: 0,
    truncated: 0,
    duration_s: 0
};

// ---------- 1. sous-comptes ----------
var accounts = [], page = 0, total = 1, apiTotal = 0;

while (accounts.length < total && page < 20) {
    var q = '/api/v1/sub-accounts/?page=' + page + '&size=100';
    if (includeDeleted) {
        q += '&includeDeleted=true';
    }
    var resp = apiGet(q);
    var batch = items(resp);

    for (var i = 0; i < batch.length; i++) {
        accounts.push(batch[i]);
    }
    total = totalOf(resp, accounts.length);
    apiTotal = total;
    page++;

    if (batch.length === 0) {
        break;
    }
}

out.accounts_total = apiTotal;

// filtre optionnel sur le statut, applique AVANT d'aller chercher les buckets
if (statusFilter !== '') {
    var wanted = statusFilter.split(',');
    var kept = [];

    for (var a = 0; a < accounts.length; a++) {
        for (var w = 0; w < wanted.length; w++) {
            if (String(accounts[a].status).toUpperCase() === wanted[w].replace(/^\s+|\s+$/g, '')) {
                kept.push(accounts[a]);
                break;
            }
        }
    }
    accounts = kept;
}

// Nombre de comptes qui DEVRAIENT etre collectes, avant plafonnement.
// La difference avec account_count est une perte silencieuse de supervision.
out.accounts_eligible = accounts.length;

if (accounts.length > maxAccounts) {
    accounts = accounts.slice(0, maxAccounts);
    out.truncated = 1;
}

// ---------- 2. buckets de chaque sous-compte ----------
for (var n = 0; n < accounts.length; n++) {
    var acc = accounts[n];
    var id = String(acc.id);

    var active = num(acc.activeStorage);
    var purchased = num(acc.purchasedStorageTB);
    var trialTb = num(acc.trialQuotaTB);

    // Un compte en essai n'a pas de purchasedStorageTB : le quota
    // applicable est alors trialQuotaTB.
    var quotaTb = null, quotaSource = 'none';

    if (purchased !== null && purchased > 0) {
        quotaTb = purchased;
        quotaSource = 'purchased';
    }
    else if (trialTb !== null && trialTb > 0) {
        quotaTb = trialTb;
        quotaSource = 'trial';
    }

    acc.quota_tb = quotaTb;
    acc.quota_source = quotaSource;
    acc.quota_pct = (active !== null && quotaTb) ? (active / quotaTb * 100) : null;

    var texp = toEpoch(acc.trialExpiration);
    acc.trial_days_left = (texp === null) ? null : Math.floor((texp - now) / 86400);

    acc.mfa = acc.mfaEnabled ? 1 : 0;
    acc.ftp = acc.ftpEnabled ? 1 : 0;
    acc.sso = acc.ssoEnabled ? 1 : 0;
    acc.bucket_count = 0;
    acc.egress = 0;
    acc.ingress = 0;
    acc.api_calls = 0;

    var bresp = apiGet('/api/v1/sub-accounts/' + encodeURIComponent(id)
        + '/buckets?latest=true&page=0&size=100');
    var blist = items(bresp);

    // pagination des buckets
    var btotal = totalOf(bresp, blist.length), bpage = 1;

    while (blist.length < btotal && bpage < 20) {
        var more = items(apiGet('/api/v1/sub-accounts/' + encodeURIComponent(id)
            + '/buckets?latest=true&page=' + bpage + '&size=100'));
        if (more.length === 0) {
            break;
        }
        for (var m = 0; m < more.length; m++) {
            blist.push(more[m]);
        }
        bpage++;
    }

    for (var b = 0; b < blist.length; b++) {
        var bk = blist[b];
        if (!bk.name) {
            continue;
        }
        var bkey = id + '/' + bk.name;
        var end = toEpoch(bk.endTime);

        bk.age_seconds = (end === null) ? -1 : (now - end);
        bk.is_deleted = bk.bucketDeleteTime ? 1 : 0;
        bk.delete_time = bk.bucketDeleteTime || '';

        acc.egress += (num(bk.egress) || 0);
        acc.ingress += (num(bk.ingress) || 0);
        acc.api_calls += (num(bk.apiCalls) || 0);

        out.buckets[bkey] = bk;
        out.discovery_buckets.push({
            '{#SUBID}': id,
            '{#SUBNAME}': acc.name || id,
            '{#BUCKET}': bk.name,
            '{#REGION}': bk.region || 'unknown',
            '{#BUCKETNUM}': String(bk.bucketNumber || '')
        });
        acc.bucket_count++;
    }

    out.accounts[id] = acc;
    out.discovery_accounts.push({
        '{#SUBID}': id,
        '{#SUBNAME}': acc.name || id,
        '{#WASABIACCT}': String(acc.wasabiAccountNumber || ''),
        '{#STATUS}': acc.status || 'UNKNOWN'
    });
}

out.account_count = out.discovery_accounts.length;
out.bucket_count = out.discovery_buckets.length;
out.duration_s = (Date.now() - t0) / 1000;

return JSON.stringify(out);
