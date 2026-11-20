"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.expect = exports.test = exports.Gxa = void 0;
const test_1 = require("@playwright/test");
Object.defineProperty(exports, "expect", { enumerable: true, get: function () { return test_1.expect; } });
let experimentList = null;
class Gxa {
    baseUrl;
    baseline = null;
    differential = new Map();
    constructor(baseUrl) {
        this.baseUrl = baseUrl.replace(/\/$/, '');
    }
    async baselineAccession() {
        if (this.baseline)
            return this.baseline;
        const experiments = await this.experiments();
        const chosen = experiments.find((item) => item.rawExperimentType === 'RNASEQ_MRNA_BASELINE') ?? experiments[0];
        const accession = chosen?.experimentAccession ?? '';
        (0, test_1.expect)(accession, 'experimentAccession missing on selected experiment').toBeTruthy();
        this.baseline = accession;
        return accession;
    }
    differentialMicroarrayAccession() {
        return this.differentialAccession('MICROARRAY_1COLOUR_MRNA_DIFFERENTIAL');
    }
    differentialRnaseqAccession() {
        return this.differentialAccession('RNASEQ_MRNA_DIFFERENTIAL');
    }
    async open(page, path) {
        const url = `${this.baseUrl}${path.startsWith('/') ? path : `/${path}`}`;
        const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120_000 });
        (0, test_1.expect)(response, `no response for ${url}`).toBeTruthy();
        (0, test_1.expect)(response.ok(), `${url} returned HTTP ${response.status()}`).toBeTruthy();
        await (0, test_1.expect)(page.locator('h4', { hasText: 'Error:' })).toHaveCount(0);
        return response;
    }
    async expectExperiment(page, accession) {
        (0, test_1.expect)(page.url(), `${accession} missing from ${page.url()}`).toContain(accession);
        await page.locator('#experimentDescription').waitFor({ state: 'visible' });
        await page.locator('#experiment-page').waitFor({ state: 'attached' });
        (0, test_1.expect)(await page.content(), `${accession} missing from experiment page HTML`).toContain(accession);
    }
    async expectSearchResults(page, example) {
        await (0, test_1.expect)(page).toHaveTitle(/Search results/);
        await (0, test_1.expect)(page.locator('h4', { hasText: 'Error:' })).toHaveCount(0);
        await (0, test_1.expect)(page.getByText('Sorry, we could not find results matching your search criteria')).toHaveCount(0);
        const core = example.split(' (', 1)[0];
        const url = page.url();
        if (url.includes('/genes/') || url.includes('/genesets/')) {
            const name = page.locator('.gxaBioentityName');
            await name.waitFor({ state: 'visible' });
            (0, test_1.expect)((await name.innerText()).trim(), `${example} gene page had an empty name`).toBeTruthy();
            if (url.includes('/genesets/')) {
                const shown = await name.innerText();
                (0, test_1.expect)(url.includes(core) || shown.includes(core), `${example} geneset page did not mention ${core}`).toBeTruthy();
                if (example.includes(' (')) {
                    const label = example.split(' (', 2)[1].replace(/\)$/, '');
                    const description = page.locator('.gxaBioentityDescription');
                    await description.waitFor({ state: 'visible' });
                    await (0, test_1.expect)(description).toContainText(label);
                }
            }
        }
        else {
            const term = page.locator('.searchterm');
            await term.waitFor({ state: 'visible' });
            await (0, test_1.expect)(term).toContainText(core);
        }
        await this.expectExpressionResults(page, example);
        await this.dismissBanner(page);
    }
    async expectHeatmap(page) {
        await page.locator('#experiment-page .gxaHeatmapContainer .highcharts-container').first().waitFor({
            state: 'visible',
            timeout: 90_000,
        });
        await page.locator('#experiment-page .gxaHeatmapContainer .highcharts-point').first().waitFor({
            state: 'visible',
            timeout: 90_000,
        });
        await this.dismissBanner(page);
    }
    async dismissBanner(page) {
        const banner = page.getByText('I agree, dismiss this banner');
        if (await banner.count())
            await banner.first().click();
    }
    async hasTab(page, tab) {
        await page.locator('#experiment-page .tabs-title').first().waitFor({ state: 'visible', timeout: 60_000 });
        return (await page.locator('#experiment-page .tabs-title', { hasText: tab }).count()) > 0;
    }
    async expectExpressionResults(page, example) {
        const differentialOnly = (await page.locator('#differential.is-active').count()) > 0 &&
            (await page.locator('#baseline.is-active').count()) === 0;
        if (differentialOnly) {
            await page.locator('#gxaDifferentialTab .gxaDifferentialResultsTable tbody tr').first().waitFor({
                state: 'visible',
                timeout: 120_000,
            });
            return;
        }
        await page.locator('#gxaBaselineTab h4', { hasText: 'Filter your results' }).waitFor({
            state: 'visible',
            timeout: 60_000,
        });
        if ((await page.locator('#gxaBaselineTab h5').count()) === 0) {
            const url = page.url();
            (0, test_1.expect)(url.includes('/genes/') || url.includes('/genesets/'), `${example} baseline tab had no facets at ${url}`).toBeTruthy();
            return;
        }
        await page.locator('#baseline.is-active .highcharts-point').first().waitFor({
            state: 'visible',
            timeout: 120_000,
        });
    }
    async differentialAccession(rawType) {
        const cached = this.differential.get(rawType);
        if (cached)
            return cached;
        const matches = (await this.experiments()).filter((item) => item.rawExperimentType === rawType);
        (0, test_1.expect)(matches.length, `no ${rawType} experiment in GET /json/experiments`).toBeGreaterThan(0);
        const human = matches.filter((item) => item.species === 'Homo sapiens' && (item.numberOfAssays ?? 0) >= 20);
        const accession = (human[0] ?? matches[0]).experimentAccession ?? '';
        (0, test_1.expect)(accession, `experimentAccession missing on ${rawType}`).toBeTruthy();
        this.differential.set(rawType, accession);
        return accession;
    }
    async experiments() {
        if (experimentList)
            return experimentList;
        const response = await fetch(`${this.baseUrl}/json/experiments`);
        (0, test_1.expect)(response.ok, `GET /json/experiments returned HTTP ${response.status}`).toBeTruthy();
        const body = (await response.json());
        const experiments = body.experiments ?? [];
        (0, test_1.expect)(experiments.length, 'GET /json/experiments returned an empty experiments list').toBeGreaterThan(0);
        experimentList = experiments;
        return experiments;
    }
}
exports.Gxa = Gxa;
exports.test = test_1.test.extend({
    gxa: async ({}, use) => {
        const baseUrl = process.env.GXA_SYSTEM_BASE?.replace(/\/$/, '');
        if (!baseUrl) {
            throw new Error('GXA_SYSTEM_BASE is not set. Set it in .env or the environment.');
        }
        await use(new Gxa(baseUrl));
    },
});
