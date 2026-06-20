import re

with open("FinalPaper.tex", "r", encoding="utf-8") as f:
    content = f.read()

english_abstract = r"""\bibliographystyle{unsrt}
\bibliography{ref}

\newpage
\twocolumn[
  \begin{@twocolumnfalse}\vspace*{1cm}
\parbox{\textwidth}{
\xiaosihao\ArialFont\textbf{Research on Video Stabilization Algorithm Based on VLFeat and Wiener Deconvolution}
\vspace*{0.3cm}

{\xiaosihao ZHANG Mou\makebox{$^{\text{1, *}}$}, LYU Moumou\makebox{$^{\text{2}}$}, ZHUGE Mou\makebox{$^{\text{1}}$}, OUYANG Moumou\makebox{$^{\text{1}}$} \mycolorBlue{\wuhao\textbf{ (投稿时请将作者信息删除)}}}\\[0.3cm]
\xiaowuhao{
1. {\textit{\ArialFont College of Aerospace Engineering, Nanjing University of Aeronautics and Astronautics, Nanjing 210016, China}}

2. \textbf{\textsl{\ArialFont School of Aeronautic Science and Engineering, Beihang University, Beijing 100191, China}}}

\vspace*{2.0cm}

\xiaowuhao
{
\renewcommand{\baselinestretch}{0.8}
\ArialFont
\textbf{Abstract:} 
Video stabilization and deblurring are critical research topics in computer vision fields such as drone reconnaissance and handheld filming. Aiming at the problem of image blurring caused by high-frequency random camera shake and rapid movement in actual recordings, this paper proposes a three-stage modular video stabilization pipeline. Initially, a self-developed inter-frame optical flow and corner detection code was attempted, but due to limited precision in feature point extraction, poor robustness against scale and rotation changes, and high sensitivity to dynamic foreground outliers, the stabilization results were suboptimal. Therefore, the authoritative VLFeat algorithm library was introduced. By leveraging its efficient and high-precision SIFT (Scale-Invariant Feature Transform) feature extraction algorithm, combined with RANSAC robust model fitting, a highly robust inter-frame 6-DoF affine transformation model was constructed. On this basis, a filtering module incorporating absolute motion trajectory accumulation and zero-phase Gaussian smoothing of decomposed parameters was designed. Concurrently, to combat linear motion blur induced by rapid shaking, an advanced image enhancement strategy was proposed, which inversely deduces the physical Point Spread Function (PSF) from global geometric transformation residuals and utilizes frequency-domain Wiener filtering combined with Edgetaper for non-blind deconvolution. Experimental results demonstrate that under three synthetic shaking scenarios—handheld walking, bumpy riding, and severe camera shake—the total translation Root Mean Square Error (RMSE) after stabilization was significantly reduced to 19.22 pixels, 36.51 pixels, and 9.81 pixels, respectively. The proposed algorithm effectively filters out high-frequency jitters and restores image clarity while preserving the authentic low-frequency motion intent of the camera, thus demonstrating high potential for real-time operation and considerable engineering practical value.
 
\textbf{Keywords:} Video stabilization; Image deblurring; VLFeat library; SIFT feature extraction; Wiener deconvolution; RANSAC
}
}
\positiontextbox{2.0cm}{22cm}{
\noindent\hdashrule{7.5cm}{0.6pt}{2.5pt 0.8pt}\\[3.5ex]%
 \xiaowuhao \linespread{0.8}\selectfont
\parbox{\textwidth}{%
\CalibriFont
\makebox[\widthof{\makebox{*}R}][r]{R}eceived: 2026-06-01; Revised: 2026-xx-xx; Accepted: 2026-xx-xx; \\%
\makebox[\widthof{\makebox{*}U}][r]{U}RL: http://hkxb.buaa.edu.cn/CN/html/2026XXXX.html\\
\makebox[\widthof{\makebox{*}F}][r]{F}oundation item: National Natural Science Foundation of China (12345678); China Postdoctoral Science Foundation(87654321)\\ 
\makebox[\widthof{\makebox{*}C}][r]{\makebox{*}C}orresponding author. ~~ E-mail: hkxb@buaa.edu.cn
}}
  \end{@twocolumnfalse}
]
\end{document}"""

content = content.replace("\\end{document}", english_abstract)
with open("FinalPaper.tex", "w", encoding="utf-8") as f:
    f.write(content)
