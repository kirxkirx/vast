import logging
import re
import unittest
from pathlib import Path
from urllib.parse import urlparse

import requests
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait


# ---------- logging -----------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
LOG = logging.getLogger(__name__)

# ---------- configuration ----------------------------------------------
REPORT_HTML = Path.cwd() / "transient_report" / "index.html"
assert REPORT_HTML.is_file(), (
    "Cannot find " + str(REPORT_HTML)
    + ". Run the test from the directory that contains transient_report/."
)
PAGE_URL = REPORT_HTML.resolve().as_uri()

SKIP_LINK_PATTERNS = (
    "cbat.eps.harvard.edu/tocp_report",
    "wis-tns.weizmann.ac.il",
)

REQUEST_TIMEOUT   = 30   # seconds for each HTTP HEAD
CHECK_EXTERNAL    = True # set False for offline / quick run
MPC_PAGE_TIMEOUT  = 120  # seconds to wait for MPC page
VSX_PAGE_TIMEOUT  = 120  # seconds to wait for VSX page


class SecondSectionLinkButtonTest(unittest.TestCase):
    # ----- set up / tear down ------------------------------------------
    @classmethod
    def setUpClass(cls):
        LOG.info("Starting Chrome in headless mode ...")
        # -------- headless setup ---------------------------------------
        opts = Options()
        # for Chrome >= 109 use "headless=new"; for older versions "headless" also works
        opts.add_argument("--headless=new")
        # optionally disable gpu & dev-shm if your CI container needs it
        opts.add_argument("--disable-gpu")
        opts.add_argument("--disable-dev-shm-usage")

        cls.driver = webdriver.Chrome(options=opts)      # pass options here
        cls.driver.implicitly_wait(3)

    @classmethod
    def tearDownClass(cls):
        LOG.info("Closing browser.")
        cls.driver.quit()

    # ----- helpers ------------------------------------------------------
    def _find_section_root(self):
        drv = self.driver
        LOG.info("Locating section that contains the line 'V0615 Vul' ...")
        vul_line = drv.find_element(
            By.XPATH, "//pre[contains(normalize-space(.), 'V0615 Vul')]"
        )
        anchor = vul_line.find_element(By.XPATH, "./preceding::a[@name][1]")
        LOG.info("Section anchor: #%s", anchor.get_attribute("name"))
        return anchor

    def _collect_section_elements(self, anchor):
        drv = self.driver
        elems = []
        node = drv.execute_script("return arguments[0].nextElementSibling;", anchor)
        while node and node.tag_name.lower() != "hr":
            elems.append(node)
            node = drv.execute_script("return arguments[0].nextElementSibling;", node)
        return elems

    # ----- main test ----------------------------------------------------
    def test_links_and_buttons(self):
        drv = self.driver
        LOG.info("Loading %s", PAGE_URL)
        drv.get(PAGE_URL)

        anchor = self._find_section_root()
        section_nodes = self._collect_section_elements(anchor)

        # Check for required text in section
        section_text = ""
        for node in section_nodes:
            section_text += node.text + " "
        
        self.assertIn("V0615 Vul", section_text)
        self.assertIn("PNV J19430751+2100204", section_text)
        self.assertIn("Type: N", section_text)
        LOG.info("Required text found in section.")

        links, forms = set(), set()
        for n in section_nodes:
            links.update(n.find_elements(By.XPATH, ".//a"))
            if n.tag_name.lower() == "a":
                links.add(n)
            forms.update(n.find_elements(By.XPATH, ".//form"))
            if n.tag_name.lower() == "form":
                forms.add(n)

        LOG.info("Found %d links and %d forms in this section.",
                 len(links), len(forms))

        # ----- link checks ----------------------------------------------
        for idx, a in enumerate(sorted(links, key=lambda x: x.get_attribute("href")), 1):
            href = a.get_attribute("href")
            LOG.info("(%2d/%d) Checking link: %s", idx, len(links), href)
            self.assertTrue(href, "<a> without href attribute")

            parsed = urlparse(href)

            # 1) skip explicit blacklist
            if any(pat in href for pat in SKIP_LINK_PATTERNS):
                LOG.info(" -- skipped (in skip list)")
                continue

            # 2) javascript toggle
            if href.startswith("javascript:"):
                match = re.search(r"toggleElement\('([^']+)'\)", href)
                self.assertIsNotNone(match, "Unexpected javascript link " + href)
                tgt_id = match.group(1)
                tgt = drv.find_element(By.ID, tgt_id)
                before_display = tgt.value_of_css_property("display")
                a.click()
                WebDriverWait(drv, 2).until(
                    lambda d: tgt.value_of_css_property("display") != before_display
                )
                a.click()
                WebDriverWait(drv, 2).until(
                    lambda d: tgt.value_of_css_property("display") == before_display
                )

            # 3) internal anchor (file://...#frag or just #frag)
            elif parsed.scheme in ("", "file") and parsed.fragment:
                cur_url = drv.current_url
                a.click()
                self.assertIn("#" + parsed.fragment, drv.current_url)
                drv.execute_script("window.history.back()")
                WebDriverWait(drv, 2).until(lambda d: d.current_url == cur_url)

            # 4) external HTTP(S) link
            elif parsed.scheme in ("http", "https"):
                if not CHECK_EXTERNAL:
                    LOG.info(" -- skipped (external checks disabled)")
                    continue
                try:
                    resp = requests.head(href, allow_redirects=True,
                                         timeout=REQUEST_TIMEOUT)
                    self.assertLess(
                        resp.status_code, 400,
                        "%s -> HTTP %d" % (href, resp.status_code)
                    )
                except requests.RequestException as exc:
                    self.fail("Broken link %s: %s" % (href, exc))

            # 5) unsupported scheme
            else:
                LOG.info(" -- skipped (unsupported scheme %s)", parsed.scheme)

        # ----- form checks ----------------------------------------------
        for idx, form in enumerate(forms, 1):
            action = form.get_attribute("action")
            LOG.info("Checking form %d/%d (action=%s)", idx, len(forms), action)
            self.assertTrue(action, "form without action attribute")
            submits = form.find_elements(
                By.XPATH,
                ".//input[translate(@type,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='submit']"
                " | .//button[@type='submit']"
            )
            self.assertGreater(len(submits), 0,
                               "form without submit button [%s]" % action)

        # special submissions
        self._check_mpc_submission(section_nodes)
        self._check_vsx_submission(section_nodes)

    # ----- MPC submission ----------------------------------------------
    def _check_mpc_submission(self, section_nodes):
        drv = self.driver
        LOG.info("Submitting Online MPChecker form ...")

        mpc_submit = self._find_submit(section_nodes, "Online MPChecker")
        self.assertIsNotNone(mpc_submit, "Online MPChecker button not found")

        self._submit_and_check(
            mpc_submit,
            MPC_PAGE_TIMEOUT,
            lambda src: "No known minor planets" in src,
            "The MPC page does not contain 'No known minor planets'"
        )
        LOG.info("'No known minor planets' found in MPC page.")

    # ----- VSX submission ----------------------------------------------
    def _check_vsx_submission(self, section_nodes):
        drv = self.driver
        LOG.info("Submitting VSX form ...")

        vsx_submit = self._find_submit(section_nodes, "Search VSX online")
        self.assertIsNotNone(vsx_submit, "VSX submit button not found")

        self._submit_and_check(
            vsx_submit,
            VSX_PAGE_TIMEOUT,
            lambda src: "V0615 Vul" in src,
            "VSX page does not contain 'V0615 Vul'"
        )
        LOG.info("'V0615 Vul' found in VSX page.")

    # ----- generic helpers ---------------------------------------------
    def _find_submit(self, section_nodes, label_starts_with):
        for node in section_nodes:
            try:
                return node.find_element(
                    By.XPATH,
                    ".//input[translate(@type,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='submit'"
                    " and starts-with(normalize-space(@value), '%s')]" % label_starts_with
                )
            except Exception:
                pass
        return None

    def _submit_and_check(self, submit_elem, timeout, page_test, fail_msg):
        drv = self.driver
        main_handle = drv.current_window_handle
        before_handles = set(drv.window_handles)

        submit_elem.click()

        # wait for new window/tab
        WebDriverWait(drv, 10).until(
            lambda d: len(d.window_handles) > len(before_handles)
        )
        new_handle = (set(drv.window_handles) - before_handles).pop()
        drv.switch_to.window(new_handle)

        # wait for page source to satisfy condition
        WebDriverWait(drv, timeout).until(lambda d: page_test(d.page_source))
        self.assertTrue(page_test(drv.page_source), fail_msg)

        # close new tab and return
        drv.close()
        drv.switch_to.window(main_handle)


if __name__ == "__main__":
    unittest.main()
