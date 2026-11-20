"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const fixtures_1 = require("../fixtures");
const GENE_EXAMPLES = [
    'REG1B',
    'zinc finger',
    'O14777 (UniProt)',
    'GO:0010468 (regulation of gene expression)',
];
const CONDITION_EXAMPLES = ['lung', 'leaf', 'valproic acid', 'cancer'];
const SPECIFIC_GENE = 'REG1B';
const HOMO_SAPIENS = 'Homo sapiens';
function column(page, inputId) {
    return page.locator(`#${inputId}`).locator("xpath=ancestor::div[contains(@class, 'columns')][1]");
}
async function exampleLabels(page, inputId) {
    const links = column(page, inputId).getByRole('link');
    return (await links.allInnerTexts()).map((text) => text.trim());
}
async function searchExample(page, gxa, inputId, example) {
    await gxa.open(page, '/home');
    const link = column(page, inputId).getByRole('link', { name: example, exact: true });
    await Promise.all([
        page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 120_000 }),
        link.click(),
    ]);
    await gxa.expectSearchResults(page, example);
}
function searchPath(options) {
    const params = new URLSearchParams();
    if (options.gene !== undefined) {
        params.set('geneQuery', JSON.stringify([{ value: options.gene }]));
    }
    if (options.condition !== undefined) {
        params.set('conditionQuery', JSON.stringify([{ value: options.condition }]));
    }
    if (options.species !== undefined)
        params.set('species', options.species);
    return `/search?${params.toString()}`;
}
(0, fixtures_1.test)('1. Search examples listed for genes and biological conditions.', async ({ page, gxa }) => {
    await gxa.open(page, '/home');
    (0, fixtures_1.expect)(await exampleLabels(page, 'home-search-gene-query-input')).toEqual(GENE_EXAMPLES);
    (0, fixtures_1.expect)(await exampleLabels(page, 'home-search-condition-query-input')).toEqual(CONDITION_EXAMPLES);
});
for (const example of GENE_EXAMPLES) {
    (0, fixtures_1.test)(`1. Search a gene example from the home form. (${example})`, async ({ page, gxa }) => {
        await searchExample(page, gxa, 'home-search-gene-query-input', example);
    });
}
for (const example of CONDITION_EXAMPLES) {
    (0, fixtures_1.test)(`1. Search a biological-condition example from the home form. (${example})`, async ({ page, gxa }) => {
        await searchExample(page, gxa, 'home-search-condition-query-input', example);
    });
}
(0, fixtures_1.test)('2. Specific gene with species set to Homo sapiens: gene information tab.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ gene: SPECIFIC_GENE, species: HOMO_SAPIENS }));
    await gxa.expectSearchResults(page, SPECIFIC_GENE);
    await (0, fixtures_1.expect)(page.locator("a[href='#information']")).toBeVisible({ timeout: 60_000 });
});
(0, fixtures_1.test)('3. Same gene with species left as Any: results still render.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ gene: SPECIFIC_GENE, species: '' }));
    await gxa.expectSearchResults(page, SPECIFIC_GENE);
});
(0, fixtures_1.test)('4. Multi-hit gene search: toggle one facet and the heatmap is still drawn.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ gene: 'zinc finger' }));
    await gxa.expectSearchResults(page, 'zinc finger');
    const facet = page.locator('#gxaBaselineTab input[type=checkbox]').first();
    await facet.waitFor({ state: 'visible', timeout: 60_000 });
    await facet.click();
    await page.locator('#baseline.is-active .highcharts-point').first().waitFor({ state: 'visible', timeout: 120_000 });
});
(0, fixtures_1.test)('5. Condition search with a species selected.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ condition: 'lung', species: HOMO_SAPIENS }));
    await gxa.expectSearchResults(page, 'lung');
});
(0, fixtures_1.test)('6. Same condition with species left as Any.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ condition: 'lung', species: '' }));
    await gxa.expectSearchResults(page, 'lung');
});
(0, fixtures_1.test)('7. Condition with Baseline and Differential: open each and toggle one filter.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ condition: 'lung' }));
    await gxa.expectSearchResults(page, 'lung');
    const baselineFacet = page.locator('#gxaBaselineTab input[type=checkbox]').first();
    await baselineFacet.waitFor({ state: 'visible', timeout: 60_000 });
    await baselineFacet.click();
    await page.locator('#baseline.is-active .highcharts-point').first().waitFor({ state: 'visible', timeout: 120_000 });
    await page.locator("a[href='#differential']").click();
    await page.locator('#differential.is-active h4', { hasText: 'Filter your results' }).waitFor({
        state: 'visible',
        timeout: 120_000,
    });
    const differentialFacet = page.locator('#gxaDifferentialTab input[type=checkbox]:not([disabled])').first();
    await differentialFacet.waitFor({ state: 'visible', timeout: 120_000 });
    await differentialFacet.click();
    await page
        .locator('#differential.is-active .gxaDifferentialResultsTable tbody tr, #differential.is-active .highcharts-point')
        .first()
        .waitFor({ state: 'visible', timeout: 120_000 });
});
(0, fixtures_1.test)('8. Hover one baseline heatmap cell: a tooltip is visible.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ condition: 'lung' }));
    await gxa.expectSearchResults(page, 'lung');
    await page.locator('#baseline.is-active .highcharts-point').first().hover();
    await (0, fixtures_1.expect)(page.locator('.highcharts-tooltip').first()).toBeVisible();
});
(0, fixtures_1.test)('9. Click one experiment link in the baseline heatmap.', async ({ page, gxa }) => {
    await gxa.open(page, searchPath({ condition: 'lung' }));
    await gxa.expectSearchResults(page, 'lung');
    const link = page.locator("#gxaBaselineTab a[href*='/experiments/E-']").first();
    await link.waitFor({ state: 'visible', timeout: 60_000 });
    const href = (await link.getAttribute('href')) ?? '';
    const match = href.match(/(E-[A-Z0-9-]+)/);
    (0, fixtures_1.expect)(match, href).toBeTruthy();
    await Promise.all([
        page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 90_000 }),
        link.click(),
    ]);
    await gxa.expectExperiment(page, match[1]);
});
