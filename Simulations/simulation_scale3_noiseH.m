
% read image
I0 = (imread('resolution.tif'));

%%
%%%%%%%%%%%%%%%%%%%%%% image degradation %%%%%%%%%%%%%%%%%%%%
sf = 3; % scale factor
I0  = modcrop((I0), sf);

kernelsigma = 1.6;     % width (sigma) of the Gaussian blur kernel
k       = fspecial('gaussian', 7, kernelsigma);
blur_HR   = imfilter(I0,k,'circular'); 
LR        = downsample2(blur_HR, sf);  % downsampled

% noise parameters
noisesigma  = 20/255;   % default, no noise

randn('seed',0);
Noise = noisesigma*randn(size(LR));
LR_noisy  = im2double(LR) + Noise;

% 
imshow(LR_noisy,[])

%%
%%%%%%%%%%%%%%%%%%%%%% Cubic Super Resolution %%%%%%%%%%%%%%%%%%%%
disp('========== Bicubic ============');
HR_bic     = imresize(LR_noisy,sf,'bicubic');
% HR_bic_shave = (shave((HR_bic), [sf, sf]));
imshow(HR_bic,[]);


%% Proposed
%{,
disp('========== Proposed ============');
Isigma      = 22/255; % default 0.5/255 for noise-free case. It should be larger than noisesigma, e.g., Isigma = noisesigma + 2/255;
Isigma      = max(Isigma,0.1/255);
Msigma      = 30;    % noise level of last denoiser

% default parameter setting of HQS
totalIter   = 50;
modelSigmaS = logspace(log10(50),log10(Msigma),totalIter);
ns          = min(25,max(ceil(modelSigmaS/2),1));
ns          = [ns(1)-1,ns];
lamda       = (Isigma^2)/3; % default 3, ****** from {1 2 3 4} ******

y = im2single(LR_noisy);
[rows_in,cols_in,~] = size(y);
rows      = rows_in*sf;
cols      = cols_in*sf;
[G,Gt]    = defGGt(double(k),sf);
GGt       = constructGGt(k,sf,rows,cols);
Gty       = Gt(y);
useGPU      = 0; % 1 or 0, true or false

if useGPU
    input = gpuArray(input);
    GGt   = gpuArray(GGt);
    Gty   = gpuArray(Gty);
end
% input (single)
input      = im2single(HR_bic);
output    = input;

% main loop, denoising with FFDNet
% set noise level map
global sigmas;
sigmas = Isigma;

tic;
load(fullfile('Denoiser/FFDNet/models','FFDNet_gray.mat'));
net = vl_simplenn_tidy(net);

for itern = 1:totalIter
    itern
    % step 1, closed-form solution, see Chan et al. [1] for details
    rho    = lamda*255^2/(modelSigmaS(itern)^2);
    rhs    = Gty + rho*output;
    output = (rhs - Gt(real(ifft2(fft2(G(rhs))./(GGt + rho)))))/rho;

    % step 2, perform denoising
    res    = my_vl_simplenn(net,output,[],[],'conserveMemory',true,'mode','test');
    im     = res(end).x;
    output = im;
    
    imshow((output),[])
    title(['Iteration: ' num2str(itern) ', PSNR: ' num2str(aux_PSNR(double(output*255), double(I0))) ' dB']);
    drawnow;
end

if useGPU
    output = gather(output);
end
toc;

HR_Proposed = double(output)*255;
% HR_Proposed = double(shave(HR_Proposed, [sf, sf]));
%}
%% SPMSR
%{,
disp('========== SPMSR ============');

im_gnd = modcrop(I0, sf);
im_gnd = single(im_gnd)/255;

im_l = imresize(im_gnd, 1/sf, 'bicubic');
% im_b = imresize(im_l, sf, 'bicubic');
im_n = im_l + Noise;

HR_SPMSR = Interface_SPMSR(im_n, sf);
% HR_SPMSR = shave(HR_SPMSR, [sf, sf]);
%}

%% SRCNN
disp('========== SRCNN ============');
% set parameters
if sf == 2
    model = 'model/9-5-5(ImageNet)/x2.mat';
elseif sf ==3
    model = 'model/9-5-5(ImageNet)/x3.mat';
end

im_gnd = modcrop(I0, sf);
im_gnd = single(im_gnd)/255;

im_l = imresize(im_gnd, 1/sf, 'bicubic');
im_n = im_l + Noise;

im_b = imresize(im_n, sf, 'bicubic');


HR_SRCNN = SRCNN(model, im_b);


%%
subplot(2,2,1); imshow(double(I0),[]);
subplot(2,2,2); imshow(LR_noisy,[]);
subplot(2,2,3); imshow(HR_bic,[]);
subplot(2,2,4); imshow(HR_Proposed,[]);

disp('PSNR results:');
PSNR_bic = aux_PSNR(HR_bic*255, double(I0))
PSNR_proposed = aux_PSNR(HR_Proposed, double(I0))
PSNR_SPMSR = aux_PSNR(double(HR_SPMSR*255), double(I0)) % a small shift fix
PSNR_SRCNN = aux_PSNR(double(HR_SRCNN*255), double(I0)) % a small shift fix

return


