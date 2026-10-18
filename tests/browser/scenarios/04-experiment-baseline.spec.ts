import type { Page } from '@playwright/test';
import { test, expect, type Gxa } from '../fixtures';

async function openExperiment(page: Page, gxa: Gxa, accession: string, tab = 'Results'): Promise<void> {
  await gxa.open(page, `/experiments/${accession}/${encodeURIComponent(tab)}`);
  await gxa.expectExperiment(page, accession);
}

test('19. Accession and experiment description are visible.', async ({ page, gxa }) => {
  const accession = await gxa.baselineAccession();
  await openExperiment(page, gxa, accession);
  const description = page.locator('#experimentDescription');
  await expect(description).toBeVisible();
  const text = `${await description.innerText()}\n${await page.content()}`;
  expect(text).toContain(accession);
});

test('20. Results heatmap has points.', async ({ page, gxa }) => {
  await openExperiment(page, gxa, await gxa.baselineAccession());
  await gxa.expectHeatmap(page);
});

test('21. Hover a heatmap cell: a tooltip is visible.', async ({ page, gxa }) => {
  await openExperiment(page, gxa, await gxa.baselineAccession());
  await gxa.expectHeatmap(page);
  await page.locator('#experiment-page .gxaHeatmapContainer .highcharts-point').first().hover();
  await expect(page.locator('.highcharts-tooltip').first()).toBeVisible();
});

test('22. Search one gene symbol, then two together.', async ({ page, gxa }) => {
  await openExperiment(page, gxa, await gxa.baselineAccession());
  await gxa.expectHeatmap(page);
  const genes = page.locator("#experiment-page a[href*='/genes/']");
  await genes.first().waitFor({ state: 'visible', timeout: 30_000 });
  const first = (await genes.nth(0).innerText()).trim();
  const second = (await genes.nth(1).innerText()).trim();
  const box = page.locator('#gene-autocomplete');
  await box.click();
  await box.fill(first);
  await box.press('Enter');
  await page.getByRole('button', { name: 'Apply' }).click();
  await expect(page.getByText(first).first()).toBeVisible();
  await box.fill(second);
  await box.press('Enter');
  await page.getByRole('button', { name: 'Apply' }).click();
  const body = await page.locator('#experiment-page').innerText();
  expect(body).toContain(first);
  expect(body).toContain(second);
});

test('23. Toggle one experimental-variable filter.', async ({ page, gxa }) => {
  await openExperiment(page, gxa, await gxa.baselineAccession());
  await gxa.expectHeatmap(page);
  const selected = page.getByText(/Selected: \d+ \/ \d+/).first();
  const before = await selected.innerText();
  await page.getByRole('button', { name: 'Select' }).click();
  await page.locator('[role=dialog] input[type=checkbox]').first().evaluate((el: HTMLElement) => el.click());
  await page.locator('[role=dialog]').first().getByRole('button', { name: 'Apply' }).click();
  await expect(selected).not.toHaveText(before, { timeout: 30_000 });
});

test('31. Plots tab: open one pre-generated plot and assert it renders.', async ({ page, gxa }) => {
  const accession = await gxa.differentialRnaseqAccession();
  await openExperiment(page, gxa, accession, 'Plots');
  expect(await gxa.hasTab(page, 'Plots')).toBeTruthy();
  const plot = page.locator("#experiment-page a[href*='PLOT']").first();
  await plot.waitFor({ state: 'visible', timeout: 60_000 });
  const href = (await plot.getAttribute('href')) ?? '';
  const url = href.startsWith('http') ? href : new URL(href, gxa.baseUrl).toString();
  const response = await page.request.get(url, { timeout: 60_000 });
  expect(response.ok(), `${url} returned HTTP ${response.status()}`).toBeTruthy();
  const contentType = response.headers()['content-type'] ?? '';
  const body = await response.body();
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
  expect(contentType.startsWith('image/') || body.subarray(0, 4).equals(png), contentType).toBeTruthy();
});

test('33. Supplementary information tab renders its panel.', async ({ page, gxa }) => {
  await openExperiment(page, gxa, await gxa.baselineAccession(), 'Supplementary Information');
  expect(await gxa.hasTab(page, 'Supplementary Information')).toBeTruthy();
  const panel = page.locator('#experiment-page');
  await expect(panel).toContainText('Supplementary', { timeout: 60_000 });
  expect((await panel.innerText()).trim().length).toBeGreaterThan('Supplementary Information'.length);
});

test('34. Download tab renders its panel.', async ({ page, gxa }) => {
  await openExperiment(page, gxa, await gxa.baselineAccession(), 'Downloads');
  expect(await gxa.hasTab(page, 'Downloads')).toBeTruthy();
  await expect(page.locator('#experiment-page a[href]').first()).toBeVisible({ timeout: 60_000 });
});
