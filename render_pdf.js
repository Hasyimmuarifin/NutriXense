const puppeteer = require('puppeteer-core');
const path = require('path');

(async () => {
    try {
        const edgePath = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";
        const htmlPath = path.resolve(__dirname, 'TECHNICAL_GUIDANCE.html');
        const pdfPath = path.resolve(__dirname, 'Technical_Guidance_NutriXense.pdf');

        console.log('Launching Edge browser...');
        const browser = await puppeteer.launch({
            executablePath: edgePath,
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--allow-file-access-from-files']
        });

        const page = await browser.newPage();
        
        console.log('Loading HTML file...');
        await page.goto(`file:///${htmlPath.replace(/\\/g, '/')}`, { waitUntil: 'networkidle0' });

        console.log('Waiting for Mermaid diagrams to finish rendering...');
        try {
            await page.waitForSelector('.mermaid svg', { timeout: 10000 });
            console.log('Mermaid diagram SVG successfully rendered!');
        } catch (e) {
            console.log('Note: Mermaid selector wait finished or skipped:', e.message);
        }

        // Small delay for layout calculation
        await new Promise(r => setTimeout(r, 1500));

        console.log('Generating PDF...');
        await page.pdf({
            path: pdfPath,
            format: 'A4',
            margin: {
                top: '20mm',
                bottom: '20mm',
                left: '15mm',
                right: '15mm'
            },
            printBackground: true,
            displayHeaderFooter: true,
            headerTemplate: '<div style="font-size:8.5px; font-family: Segoe UI, sans-serif; color: #64748b; width: 100%; text-align: right; padding-right: 15mm;">NutriXense Technical Guidance</div>',
            footerTemplate: '<div style="font-size:8.5px; font-family: Segoe UI, sans-serif; color: #64748b; width: 100%; text-align: center;">Halaman <span class="pageNumber"></span> dari <span class="totalPages"></span></div>'
        });

        await browser.close();
        console.log(`SUCCESS: PDF successfully generated at:\n${pdfPath}`);
    } catch (err) {
        console.error('ERROR during PDF generation:', err);
        process.exit(1);
    }
})();
