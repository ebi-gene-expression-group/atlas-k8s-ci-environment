import type { Page } from '@playwright/test';
import { test, expect, type Gxa } from '../fixtures';

const TECHNOLOGIES = ['microarray', 'rna-seq'] as const;

async function accessionFor(gxa: Gxa, technology: (typeof TECHNOLOGIES)[number]): Promise<string> {
  return technology === 'microarray'
    ? gxa.differentialMicroarrayAccession()
    : gxa.differentialRnaseqAccession();
}

async function openResults(page: Page, gxa: Gxa, technology: (typeof TECHNOLOGIES)[number]): Promise<string> {
  const accession = await accessionFor(gxa, technology);
  await gxa.open(page, `/experiments/${accession}/Results`);
  await gxa.expectExperiment(page, accession);
  await gxa.expectHeatmap(page);
  return accession;
}

async function showing(page: Page): Promise<string> {
  const locator = page.getByText(/Showing .+ gene/).first();
  await locator.waitFor({ state: 'visible', timeout: 90_000 });
  return locator.innerText();
}

for (const technology of TECHNOLOGIES) {
  test(`25. Results heatmap has points. (${technology})`, async ({ page, gxa }) => {
    await openResults(page, gxa, technology);
  });

  test(`26. Hover a heatmap cell: a tooltip is visible. (${technology})`, async ({ page, gxa }) => {
    await openResults(page, gxa, technology);
    await page.locator('#experiment-page .gxaHeatmapContainer .highcharts-point').first().hover();
    await expect(page.locator('.highcharts-tooltip').first()).toBeVisible();
  });

  test(`27. Up/down regulation filter changes the results. (${technology})`, async ({ page, gxa }) => {
    await openResults(page, gxa, technology);
    const before = await showing(page);
    await page.locator('#menu-item-UP').click();
    await expect(page.getByText(/Showing .+ gene/).first()).not.toHaveText(before, { timeout: 60_000 });
  });

  test(`28. Change fold-change and p-value. (${technology})`, async ({ page, gxa }) => {
    await openResults(page, gxa, technology);
    const before = await showing(page);
    const texts = page.locator('#experiment-page input[type=text]');
    await texts.nth(1).fill('2');
    await texts.nth(2).fill('0.01');
    await page.getByRole('button', { name: 'Apply' }).click();
    await expect(page.getByText(/Showing .+ gene/).first()).not.toHaveText(before, { timeout: 60_000 });
  });

  test(`29. Comparisons filter changes the results. (${technology})`, async ({ page, gxa }) => {
    await openResults(page, gxa, technology);
    const selected = page.getByText(/Selected: \d+ \/ \d+/).first();
    const before = await selected.innerText();
    await page.getByRole('button', { name: 'Select' }).click();
    await page.locator('[role=dialog] input[type=checkbox]').first().evaluate((el: HTMLElement) => el.click());
    await page.locator('[role=dialog]').first().getByRole('button', { name: 'Apply' }).click();
    await expect(selected).not.toHaveText(before, { timeout: 30_000 });
  });

  test(`30. An Ensembl link on a results row has an ensembl.org href. (${technology})`, async ({ page, gxa }) => {
    const accession = await openResults(page, gxa, technology);
    const gene = page.locator("#experiment-page a[href*='/genes/']").first();
    await gene.waitFor({ state: 'visible' });
    const geneId = ((await gene.getAttribute('href')) ?? '').replace(/\/$/, '').split('/').pop() ?? '';
    expect(geneId, 'results row had no gene link').toBeTruthy();
    const redirect = `${gxa.baseUrl}/experiments/${accession}/redirect/genome-browsers?name=Ensembl&geneId=${geneId}`;
    const response = await page.request.get(redirect, { maxRedirects: 0, timeout: 60_000 });
    expect([301, 302, 303, 307, 308]).toContain(response.status());
    expect(response.headers().location ?? '').toContain('ensembl.org');
  });

  test(`32. Experiment Design tab renders its panel, including at least one comparison. (${technology})`, async ({
    page,
    gxa,
  }) => {
    const accession = await accessionFor(gxa, technology);
    await gxa.open(page, `/experiments/${accession}/${encodeURIComponent('Experiment Design')}`);
    await gxa.expectExperiment(page, accession);
    expect(await gxa.hasTab(page, 'Experiment Design')).toBeTruthy();
    await expect(page.locator('#experiment-page')).toContainText(/comparison/i, { timeout: 60_000 });
  });
}
