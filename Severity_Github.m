clear; clc; close all;

% 1. Load slice
[fNames pName] = uigetfile('.png', 'choose a png file', 'MultiSelect', 'on');
slicenames = cell(1, length(fNames));
for i = 1:length(fNames)
    slicename = fNames{i};
    slicename = slicename(1:end-4);
    spaceIn = findstr(slicename, ' ');
    if spaceIn
        slicename = slicename(1:spaceIn-1);
    end
    slicenames{i} = slicename;
end
[uniqueNames, idx] = unique(slicenames, 'stable');
S = struct();
for i = 1:length(uniqueNames)
    S(i).fileName = uniqueNames{i};
end

% 2. Compute threshold
results = compute_slice_thresholds(S);

% 3. All threshold
disp('Each threshold:');
for i = 1:length(results.slice_names)
    if ~isnan(results.TH_low(i))
        fprintf('  %s: Low TH=%.4f, High TH=%.4f\n', ...
            results.slice_names{i}, results.TH_low(i), results.TH_high(i));
    end
end

% 4. Threshold
fprintf('\n========== Threshold finished ==========\n');
fprintf('\n=== Results ===\n');
fprintf('Total slice: %d, ', results.total_slices);
fprintf('Success: %d, ', results.valid_count);
fprintf('Failed: %d\n', length(results.failed_slices));
if ~isempty(results.failed_slices)
    fprintf('  Failed lists: %s\n', strjoin(results.failed_slices, ', '));
end
fprintf('Mean low threshold:  %.4f ± %.4f\n', results.mean_TH_low, results.std_TH_low);
fprintf('Mean high threshold: %.4f ± %.4f\n', results.mean_TH_high, results.std_TH_high);
fprintf('IP weight: %.4f\n', results.IP_weight);

% 5. Severity
Severity = export_Severity_results(S, results.mean_TH_low, results.mean_TH_high, results.IP_weight);

% 6. Export to Excel
output_path = 'Severity_results.xlsx';    
if ~isempty(Severity)
    T = cell2table(Severity, ...
        'VariableNames', {'Slice', 'ContraTotal', 'ContraNormal', 'ContraPeri', 'ContraCore', ...
                          'IpsiTotal', 'IpsiNormal', 'IpsiPeri', 'IP', 'IP_corrected', ...
                          'IpsiCore', 'IC', 'IC_corrected', 'r', 'Severity', 'NoEdemaCorrection'});
    writetable(T, output_path);
    fprintf('\nSaved to: %s\n', output_path);
    fprintf('\nMean:\n');
    fprintf('ContraTotal:  %.4f\n', mean(T.ContraTotal));
    fprintf('ContraNormal: %.4f\n', mean(T.ContraNormal));
    fprintf('IpsiNormal:   %.4f\n', mean(T.IpsiNormal));
    fprintf('IpsiPeri:     %.4f\n', mean(T.IpsiPeri));
    fprintf('IP_corrected: %.4f\n', mean(T.IP_corrected));
    fprintf('IpsiCore:     %.4f\n', mean(T.IpsiCore));
    fprintf('IC_corrected: %.4f\n', mean(T.IC_corrected));
    fprintf('Edema ratio:  %.4f\n', mean(T.r));
    fprintf('Severity:  %.4f\n', mean(T.Severity));
    fprintf('==============================\n');
else
    warning('No available data!');
end
fprintf('\nPlease open in Excel: %s\n', output_path);



%% Threshold setting
function results = compute_slice_thresholds(S)
    slice_names = {S.fileName};
    num_slices = length(slice_names);
    
    TH_low_list = zeros(num_slices, 1);
    TH_high_list = zeros(num_slices, 1);
    failed_slices = {};
    valid_count = 0;
    
    fprintf('Proceeding %d slices...\n', num_slices);
    
    for counts = 1:num_slices
        slicename = slice_names{counts};
        Contra_ori = loadRGB(slicename,  ' Contra');
        Ipsi_ori   = loadRGB(slicename,  ' Ipsi');
        Contra = Contra_ori;
        Ipsi = Ipsi_ori;
        try  
            %% ROI for Ipsi and Contra
            rPlaneContra = Contra(:, :, 1);
            rPlaneIpsi = Ipsi(:, :, 1);
            
            maxD1Contra = max(rPlaneContra');     
            maxD2Contra = max(rPlaneContra);      
            rowBgnContra = min(find(maxD1Contra)); 
            rowEndContra = max(find(maxD1Contra)); 
            colBgnContra = min(find(maxD2Contra));
            colEndContra = max(find(maxD2Contra));
            bROIContra = rPlaneContra(rowBgnContra:rowEndContra, colBgnContra:colEndContra);
            
            maxD1Ipsi = max(rPlaneIpsi');
            maxD2Ipsi = max(rPlaneIpsi);
            rowBgnIpsi = min(find(maxD1Ipsi));
            rowEndIpsi = max(find(maxD1Ipsi));
            colBgnIpsi = min(find(maxD2Ipsi));
            colEndIpsi = max(find(maxD2Ipsi));
            bROIIpsi = rPlaneIpsi(rowBgnIpsi:rowEndIpsi, colBgnIpsi:colEndIpsi);
                    
            %% register Ipsi to Contra in ROI
            % Resize
            bROIContra = Contra(rowBgnContra:rowEndContra, colBgnContra:colEndContra, 3);
            bROIIpsi = Ipsi(rowBgnIpsi:rowEndIpsi, colBgnIpsi:colEndIpsi, 3);
            bROIContra_double = im2double(bROIContra);
            bROIIpsi_double = im2double(bROIIpsi);

            bROIIpsiReg = imresize(bROIIpsi_double,[rowEndContra-rowBgnContra+1, colEndContra-colBgnContra+1]); % bicubic by default
            
            % Flip
            bROIIpsiReg = fliplr(bROIIpsiReg);
            
            bROIIpsiRegbyRow = zeros(size(bROIContra_double));
            
            % Registrate
            nRows = size(bROIContra_double, 1);
            for iRow = 1:nRows
                rowContra = bROIContra_double(iRow, :);
                colBgnContra = min(find(rowContra));
                colEndContra = max(find(rowContra));
                rowIpsi = bROIIpsiReg(iRow, :);
                colBgnIpsi = min(find(rowIpsi));
                colEndIpsi = max(find(rowIpsi));
                rowIpsiSeg = imresize(bROIIpsiReg(iRow, colBgnIpsi:colEndIpsi),...
                    [1, colEndContra-colBgnContra+1]);
                bROIIpsiRegbyRow(iRow, colBgnContra:colEndContra) = rowIpsiSeg;
            end
            % correction bROIIpsiReg with referece to bROIContra
            bROIIpsiCorrected = bROIContra_double - bROIIpsiRegbyRow;
            
            %% Threshold 1
            [x, b] = histcounts(bROIIpsiCorrected, 100);
            x_smoothed = smooth(x, 6);
            x_diff = diff(x_smoothed);
            [~, x_max_idx] = max(x);
            threshold_pixels = max(x) * 0.02;
            threshold_pixels_diff = max(x_diff) * 0.01;
            x_diff_diff = diff(x_diff);
            peak_idx_in_diff = find(diff(sign(x_diff_diff)) == -2);
            peak_idx_in_diff = peak_idx_in_diff + 2
            diff_threshold = mean(abs(x_diff)) * 0.8;
            target_idx = [];
            for i = 1:length(peak_idx_in_diff)
                if x(peak_idx_in_diff(i)) >= threshold_pixels & x_diff(peak_idx_in_diff(i)-1) >= threshold_pixels_diff
                    target_idx = i;
                    break;
                end
            end
            for i = (peak_idx_in_diff(target_idx)):length(x_diff)
                if x_diff(i) < diff_threshold
                    target_idx = i;
                    break;
                end
            end
            THi(1) = target_idx + 1;
            THi(2) = floor((x_max_idx - THi(1))/2) + THi(1);
            
            bROIIpsi3Levels = uint8(zeros(size(bROIContra)));
            % IC
            Idx = find(bROIIpsiCorrected<b(THi(1)));
            bROIIpsi3Levels(Idx) = 3;
            % IP
            Idx = find(bROIIpsiCorrected<b(THi(2)) & bROIIpsiCorrected>=b(THi(1)));
            bROIIpsi3Levels(Idx) = 2;
            %Normal tissue
            Idx = find(bROIIpsiCorrected>=b(THi(2))& bROIIpsiCorrected ~= 0);
            bROIIpsi3Levels(Idx) = 1;
                        
            % Apply
            numBins = 100;
            maskIpsi = (bROIIpsiRegbyRow > 0) & (bROIIpsiRegbyRow < 1);
            [~, edges_ipsi] = histcounts(1-bROIIpsiRegbyRow(maskIpsi), numBins);
            centers_ipsi = (edges_ipsi(1:end-1) + edges_ipsi(2:end)) / 2;

            TH_ipsi_low = centers_ipsi(THi(1));
            TH_ipsi_high = centers_ipsi(THi(2)); 

            % % show raw data;
            % figure('Name', slicename),
            % subplot(2, 5, 1); imshow(Contra_ori); title('Contra');
            % subplot(2, 5, 6); imshow(Ipsi_ori);   title('Ipsi');
            % subplot(2, 5, 2); imshow(bROIContra_double); title('RoI Contra');
            % subplot(2, 5, 3); imshow(bROIIpsi_double);   title('RoI Ipsi pre-reg');
            % subplot(2, 5, 4); imshow(bROIIpsiReg); title('RoI Ipsi size-reg');
            % subplot(2, 5, 5); imshow(bROIIpsiReg); title('RoI Ipsi fliplr');
            % subplot(2, 5, 7); imshow(bROIIpsiRegbyRow); title('RoI Ipsi shape-reg');
            % subplot(2, 5, 8); imshow(fliplr(bROIIpsiCorrected), []); title('RoI Ipsi corrected and fliplr-ed');
            % subplot(2, 5, 9); plot(b(1:end-1), x, '.-'); hold on; plot(b(1:end-1), x_smoothed, '.-'); title('hist of Ipsi-Contra');
            % hold on; plot(b(THi(1)), x(THi(1)), 'r*'); plot(b(THi(2)), x(THi(2)), 'r*'); xlim([-1 0]);
            % subplot(2, 5, 10); imshow(fliplr(bROIIpsi3Levels), [0 3]); colormap(gca, gray(4));
            % if (THi(1)+1)>=THi(2)
            %     title('There should be no IC or IP areas');
            % else
            %     title('IC in white and IP in gray')
            % end
            % 
            % 
            % %% To observe the THi
            % figure('Name', slicename), 
            % ax(1) = subplot(3, 1, 1); plot(b(1:end-1), x, '.-'); grid on;
            % hold on; plot(b(1:end-1), x_smoothed, '.-');
            % hold on; plot(b(THi), x(THi), 'r*');
            % 
            % ax(2) = subplot(3, 1, 2); plot(b(2:end-1), x_diff, '.-');
            % grid on; ylim([-200 200]);
            % hold on; plot(b(THi), x_diff(THi-1), 'r*');
            % valid_ax = ax(ishandle(ax));
            % if length(valid_ax) >= 2
            %     linkaxes(valid_ax, 'x');
            % end
            % 
            % ax(3) = subplot(3, 1, 3); plot(b(3:end-1), x_diff_diff, '.-');
            % grid on; ylim([-50 50]);
            % hold on; plot(b(THi), x_diff_diff(THi-2), 'r*');
            % valid_ax = ax(ishandle(ax));
            % if length(valid_ax) >= 2
            %     linkaxes(valid_ax, 'x');
            % end

            % close('Name', slicename);

            %% Threshold2
            bROIIpsi_double = 1 - bROIIpsi_double;
            maskIpsi = (bROIIpsi_double > 0) & (bROIIpsi_double < 1);
            [~, b] = histcounts(bROIIpsi_double(maskIpsi), 100);
            b = linspace(0, 1, 101);
            x = histcounts(bROIIpsi_double(maskIpsi), b);
            x_smoothed = smooth(x, 7);
            x_diff = diff(x_smoothed);
            [~, x_max_idx] = max(x);
            threshold_pixels = max(x) * 0.03;
            x_diff_diff = diff(smooth(x_diff, 6));
            peak_idx_in_diff = find(diff(sign(x_diff_diff)) == -2);
            peak_idx_in_diff = peak_idx_in_diff + 2;
            diff_threshold = mean(abs(x_diff)) * 1;
            target_idx = [];
            for i = 1:length(peak_idx_in_diff)
                if x_diff(peak_idx_in_diff(i)-1) >= 0 & x(peak_idx_in_diff(i)) >= threshold_pixels
                    target_idx = i;
                    break;
                end
            end
            for i = (peak_idx_in_diff(target_idx)):length(x_diff)
                if x_diff(i) < diff_threshold
                    target_idx = i;
                    break;
                end
            end
            
            numBins = 100;
            edges_ipsi = linspace(0, 1, numBins + 1);
            centers_ipsi = (edges_ipsi(1:end-1) + edges_ipsi(2:end)) / 2;
            % "Multithresh" function
            thresholds = multithresh(bROIIpsi_double(maskIpsi), 1);
            [~, min_idx] = min(abs(centers_ipsi - thresholds(1)));
            if target_idx+1 > min_idx-4
                TH_low_multithresh = thresholds(1);
            else
                [~, min_idx] = min(x_diff(target_idx+1:min_idx-4));
                if b(target_idx + 1 + min_idx) > 0.43
                    TH_low_multithresh = b(target_idx + 1);
                else
                    TH_low_multithresh = b(target_idx + 1 + min_idx);
                end
            end
            TH_high_multithresh = thresholds(1);

            Contra_seg = zeros(size(Contra(:, :, 3)));
            Ipsi_seg = zeros(size(Ipsi(:, :, 3))); 
            Contra_seg_multithresh = zeros(size(Contra(:, :, 3)));
            Ipsi_seg_multithresh = zeros(size(Ipsi(:, :, 3)));
            Contra_seg_filtered = zeros(size(Contra(:, :, 3)));
            Ipsi_seg_filtered = zeros(size(Ipsi(:, :, 3)));
            a = TH_ipsi_low;
            TH_ipsi_low = (1 - TH_ipsi_high) * 255;
            TH_ipsi_high = (1 - a) * 255;
            a = TH_low_multithresh;
            TH_low_multithresh = (1 - TH_high_multithresh) * 255;
            TH_high_multithresh = (1 - a) * 255;
            Contra_seg_size = nnz(Contra(:, :, 3) < 255 & Contra(:, :, 3) > TH_ipsi_low);
            Ipsi_seg_size = nnz(Ipsi(:, :, 3) < 255 & Ipsi(:, :, 3) > TH_ipsi_low);
            
            if ((THi(1)+1)>=THi(2))|(TH_low_multithresh>=TH_high_multithresh)|((Contra_seg_size >= Ipsi_seg_size))
                if ((THi(1)+1)>=THi(2))|((Contra_seg_size >= Ipsi_seg_size))
                    TH_low_multithresh = TH_ipsi_low;
                    TH_high_multithresh = TH_ipsi_high;
                end
                Contra_seg(Contra(:, :, 3) > 0) = 1;
                Ipsi_seg(Ipsi(:, :, 3) > 0 ) = 1;
                Contra_seg_multithresh(Contra(:, :, 3) > 0) = 1;
                Ipsi_seg_multithresh(Ipsi(:, :, 3) > 0 ) = 1;
            else
                % Contra
                Contra_seg(Contra(:, :, 3) > 0             & Contra(:, :, 3) < TH_ipsi_low)  = 1;
                Contra_seg(Contra(:, :, 3) >= TH_ipsi_low  & Contra(:, :, 3) < TH_ipsi_high) = 2;
                Contra_seg(Contra(:, :, 3) >= TH_ipsi_high & Contra(:, :, 3) < 255)        = 3;
                
                Contra_seg_multithresh(Contra(:, :, 3) > 0             & Contra(:, :, 3) < TH_low_multithresh)         = 1;
                Contra_seg_multithresh(Contra(:, :, 3) >= TH_low_multithresh  & Contra(:, :, 3) < TH_high_multithresh) = 2;
                Contra_seg_multithresh(Contra(:, :, 3) >= TH_high_multithresh & Contra(:, :, 3) < 255)               = 3;
                
                % Ipsi
                Ipsi_seg(Ipsi(:, :, 3) > 0             & Ipsi(:, :, 3) < TH_ipsi_low)  = 1;
                Ipsi_seg(Ipsi(:, :, 3) >= TH_ipsi_low  & Ipsi(:, :, 3) < TH_ipsi_high) = 2;
                Ipsi_seg(Ipsi(:, :, 3) >= TH_ipsi_high & Ipsi(:, :, 3) < 255)        = 3;
                
                Ipsi_seg_multithresh(Ipsi(:, :, 3) > 0             & Ipsi(:, :, 3) < TH_low_multithresh)         = 1;
                Ipsi_seg_multithresh(Ipsi(:, :, 3) >= TH_low_multithresh  & Ipsi(:, :, 3) < TH_high_multithresh) = 2;
                Ipsi_seg_multithresh(Ipsi(:, :, 3) >= TH_high_multithresh & Ipsi(:, :, 3) < 255)               = 3;
                
            end
                     
            TH_low_list(counts)  = TH_low_multithresh; 
            TH_high_list(counts) = TH_high_multithresh;
            if TH_ipsi_low < TH_low_multithresh
                TH_low_list(counts) =  TH_ipsi_low;
            else
                TH_low_list(counts) =  TH_low_multithresh;
            end
            if TH_ipsi_low > TH_low_multithresh & TH_ipsi_high < TH_high_multithresh
                TH_low_list(counts) =  TH_ipsi_low;
                TH_high_list(counts) = TH_high_multithresh;
            end

            Contra_seg_filtered(Contra(:, :, 3) > 0                     & Contra(:, :, 3) < TH_low_list(counts))  = 1;
            Contra_seg_filtered(Contra(:, :, 3) >= TH_low_list(counts)  & Contra(:, :, 3) < TH_high_list(counts)) = 2;
            Contra_seg_filtered(Contra(:, :, 3) >= TH_high_list(counts) & Contra(:, :, 3) < 255)                = 3;
            Ipsi_seg_filtered(Ipsi(:, :, 3) > 0                         & Ipsi(:, :, 3) < TH_low_list(counts))    = 1;
            Ipsi_seg_filtered(Ipsi(:, :, 3) >= TH_low_list(counts)      & Ipsi(:, :, 3) < TH_high_list(counts))   = 2;
            Ipsi_seg_filtered(Ipsi(:, :, 3) >= TH_high_list(counts)     & Ipsi(:, :, 3) < 255)                  = 3;
        
            if ((THi(1)+1)>=THi(2))|(TH_low_multithresh>=TH_high_multithresh)|((Contra_seg_size >= Ipsi_seg_size))
                TH_low_list(counts)  = NaN;
                TH_high_list(counts) = NaN;
                fprintf('There should be no IC or IP areas');
            else
                fprintf('  [%d/%d] %s: Low TH=%.4f, HighTH=%.4f\n', ...
                        counts, num_slices, slicename, TH_low_list(counts), TH_high_list(counts));
            end

            valid_count = valid_count + 1;
            
            % % figure
            % figure('Name', slicename), 
            % 
            % centers = (b(1:end-1) + b(2:end)) / 2;
            % [~, idx_low] = min(abs(centers - (1- (TH_low_multithresh/255))));
            % [~, idx_high] = min(abs(centers - (1- (TH_high_multithresh/255))));
            % 
            % bx(1) = subplot(3, 1, 1); plot(b(1:end-1), x, '.-'); 
            % grid on; xlim([0 1]);
            % hold on; plot(b(1:end-1), x_smoothed, '.-');
            % hold on; plot(b(idx_low), x_smoothed(idx_low), 'b*');
            % hold on; plot(b(idx_high), x_smoothed(idx_high), 'b*');
            % 
            % bx(2) = subplot(3, 1, 2); plot(b(2:end-1), x_diff, '.-');
            % grid on; ylim([-100 100]);
            % hold on; plot(b(idx_low), x_diff(idx_low-1), 'b*');
            % hold on; plot(b(idx_high), x_diff(idx_high-1), 'b*');
            % valid_bx = bx(ishandle(bx));
            % if length(valid_bx) >= 2
            %     linkaxes(valid_bx, 'x');
            % end
            % 
            % bx(3) = subplot(3, 1, 3); plot(b(3:end-1), x_diff_diff, '.-');
            % grid on; ylim([-50 50]);
            % hold on; plot(b(idx_low), x_diff_diff(idx_low-2), 'b*');
            % hold on; plot(b(idx_high), x_diff_diff(idx_high-2), 'b*');
            % valid_bx = bx(ishandle(bx));
            % if length(valid_bx) >= 2
            %     linkaxes(valid_bx, 'x');
            % end
            % figure
            figure('Name', slicename),  

            % Histogram
            subplot(2, 5, 1);
            bROIContra_double = (1 - bROIContra_double) * 255;
            maskContra = bROIContra_double > 0 & bROIContra_double < 255;
            histogram(bROIContra_double(maskContra), 100);
            xlabel('3'); ylabel('Counts');
            xlim([0 255]);
            hold on;
            xline(TH_ipsi_low, 'r--', 'LineWidth', 1.5);
            xline(TH_ipsi_high, 'r--', 'LineWidth', 1.5);
            xline(TH_low_multithresh, 'b--', 'LineWidth', 1.5);
            xline(TH_high_multithresh, 'b--', 'LineWidth', 1.5);
            if ((THi(1)+1)>=THi(2))||(TH_low_multithresh>=TH_high_multithresh)||((Contra_seg_size >= Ipsi_seg_size))
                title('There should be no IC or IP areas');
            else
                title('Contra histogram');
            end
            subplot(2, 5, 6);
            bROIIpsi_double = (1 - bROIIpsi_double) * 255;
            maskIpsi = bROIIpsi_double > 0 & bROIIpsi_double < 255;
            histogram(bROIIpsi_double(maskIpsi), 100);
            xlabel('3'); ylabel('Counts');
            xlim([0 255]);
            hold on;
            xline(TH_ipsi_low, 'r--', 'LineWidth', 1.5);
            xline(TH_ipsi_high, 'r--', 'LineWidth', 1.5);
            xline(TH_low_multithresh, 'b--', 'LineWidth', 1.5);
            xline(TH_high_multithresh, 'b--', 'LineWidth', 1.5);
            if ((THi(1)+1)>=THi(2))||(TH_low_multithresh>=TH_high_multithresh)||((Contra_seg_size >= Ipsi_seg_size))
                title('There should be no IC or IP areas');
            else
                title('Ipsi histogram');
            end

            % Masked figure
            subplot(2, 5, 2); imshow(Contra_ori); 
            title('Contra');
            subplot(2, 5, 3); imshow(Contra_seg, [0 3]); colormap(gca, gray(4)); 
            title(sprintf('Contra TH1 (Low TH<%.3f, High TH≥%.3f)', TH_ipsi_low, TH_ipsi_high));
            subplot(2, 5, 4); imshow(Contra_seg_multithresh, [0 3]); colormap(gca, gray(4)); 
            title(sprintf('Contra TH2 (Low TH<%.3f, High TH≥%.3f)', TH_low_multithresh, TH_high_multithresh));
            subplot(2, 5, 5);imshow(Contra_seg_filtered, [0 3]); colormap(gca, gray(4)); 
            title(sprintf('Contra mask (Low TH<%.3f, High TH≥%.3f)', TH_low_list(counts), TH_high_list(counts)));
            axis image;
            axis off;
            subplot(2, 5, 7); imshow(Ipsi_ori); 
            title('Ipsi');
            subplot(2, 5, 8); imshow(Ipsi_seg, [0 3]); colormap(gca, gray(4)); 
            title(sprintf('Ipsi TH1 (Low TH<%.3f, High TH≥%.3f)', TH_ipsi_low, TH_ipsi_high));
            subplot(2, 5, 9); imshow(Ipsi_seg_multithresh, [0 3]); colormap(gca, gray(4));
            title(sprintf('Ipsi TH2 (Low TH<%.3f, High TH≥%.3f)', TH_low_multithresh, TH_high_multithresh));
            subplot(2, 5, 10); imshow(Ipsi_seg_filtered, [0 3]); colormap(gca, gray(4));
            title(sprintf('Ipsi mask (Low TH<%.3f, High TH≥%.3f)', TH_low_list(counts), TH_high_list(counts)));
            axis image;
            axis off;

            % % Export threshold confirmation
            % imwrite(Contra_ori,'Contra.png');
            % imwrite(Ipsi_ori,'Ipsi.png');
            % imwrite(bROIContra_double,'RoI Contra.png');
            % imwrite(bROIIpsi_double,'RoI Ipsi pre-reg.png');
            % imwrite(bROIIpsiReg,'RoI Ipsi size-reg.png');
            % imwrite(bROIIpsiReg,'RoI Ipsi fliplr.png');
            % imwrite(bROIIpsiRegbyRow,'RoI Ipsi shape-reg.png');
            % img_normalized = mat2gray(fliplr(bROIIpsiCorrected));
            % img_uint8 = uint8(img_normalized * 255);
            % imwrite(img_uint8, 'RoI Ipsi corrected and fliplr-ed.png');
            % imwrite(fliplr(bROIIpsi3Levels),'Demo.png');

            % Image save
            % saveas(gcf, fullfile('output_folder', [slicename '.png']));
            % img = Contra_seg;img_gray = uint8(img / 3 * 255);imwrite(img_gray, 'Contra_seg.png');
            % % img = Contra_seg_multithresh;img_gray = uint8(img / 3 * 255);imwrite(img_gray, 'Contra_seg_multithresh.png');
            % img = Contra_seg_filtered;img_gray = uint8(img / 3 * 255);imwrite(img_gray, 'Contra_seg_filtered.png');
            % img = Ipsi_seg;img_gray = uint8(img / 3 * 255);imwrite(img_gray, 'Ipsi_seg.png');
            % img = Ipsi_seg_multithresh;img_gray = uint8(img / 3 * 255);imwrite(img_gray, 'Ipsi_seg_multithresh.png');
            % img = Ipsi_seg_filtered;img_gray = uint8(img / 3 * 255);imwrite(img_gray, 'Ipsi_seg_filtered.png');
            % close('Name', slicename);
        catch ME
            warning('Error: %s', slicename, ME.message);
            failed_slices{end+1} = slicename;
            TH_low_list(counts) = NaN;
            TH_high_list(counts) = NaN;
        end

        %% Statistic
        % Remove NaN
        valid_idx = ~isnan(TH_low_list) & ~isnan(TH_high_list);
        valid_low = TH_low_list(valid_idx);
        valid_high = TH_high_list(valid_idx);
        % Result
        results = struct();
        results.slice_names = slice_names;
        results.valid_count = valid_count;
        results.failed_slices = failed_slices;
        results.total_slices = num_slices;
        results.TH_low = TH_low_list;
        results.TH_high = TH_high_list;
        results.mean_TH_low = mean(valid_low);
        results.mean_TH_high = mean(valid_high);
        results.std_TH_low = std(valid_low);
        results.std_TH_high = std(valid_high);
        results.IP_weight = ((mean(valid_high) + mean(valid_low)) / 2 - (0 + mean(valid_low)) / 2) / ((255 + mean(valid_high)) / 2 - (0 + mean(valid_low)) / 2);
        
    end
end

%% Severity
function Severity_result = export_Severity_results(S, TH_low, TH_high, IP_weight)
    % Results
    %   Column 1: Slice
    %   Column 2: ContraTotal
    %   Column 3: ContraNormal
    %   Column 4: ContraPeri
    %   Column 5: ContraCore
    %   Column 6: IpsiTotal
    %   Column 7: IpsiNormal
    %   Column 8: IpsiPeri
    %   Column 9: IP
    %   Column 10: IP_corrected
    %   Column 11: IpsiCore
    %   Column 12: IC
    %   Column 13: IC_corrected
    %   Column 14: r (edema ratio
    %   Column 15: Severity (algorithm score

    % 获取所有切片名
    slice_names = {S.fileName};
    num_slices = length(slice_names);
    
    % 预分配结果数组
    Severity_result = cell(num_slices, 16);
    
    fprintf('Proceeding %d slices...\n', num_slices);
    
    valid_count = 0;
    excluded_count = 0;
    
    for i = 1:num_slices
        slicename = slice_names{i};
        try
            Contra = loadRGB(slicename, ' Contra');
            Ipsi   = loadRGB(slicename, ' Ipsi');
            Contra_s = Contra(:,:,3);
            Ipsi_s   = Ipsi(:,:,3);
            
            maskContra = (Contra_s > 0) & (Contra_s < 255);
            maskIpsi = (Ipsi_s > 0) & (Ipsi_s < 255);
            
            Contra_seg = zeros(size(Contra_s));
            Contra_seg(maskContra & Contra_s < TH_low) = 1;
            Contra_seg(maskContra & Contra_s >= TH_low & Contra_s < TH_high) = 2;
            Contra_seg(maskContra & Contra_s >= TH_high) = 3;
            
            Ipsi_seg = zeros(size(Ipsi_s));
            Ipsi_seg(maskIpsi & Ipsi_s < TH_low) = 1;
            Ipsi_seg(maskIpsi & Ipsi_s >= TH_low & Ipsi_s < TH_high) = 2;
            Ipsi_seg(maskIpsi & Ipsi_s >= TH_high) = 3;
            
            IpsiCore     = sum(Ipsi_seg(:) == 3);
            IpsiPeri     = sum(Ipsi_seg(:) == 2);
            IpsiNormal   = sum(Ipsi_seg(:) == 1);
            ContraCore   = sum(Contra_seg(:) == 3);
            ContraPeri   = sum(Contra_seg(:) == 2);
            ContraNormal = sum(Contra_seg(:) == 1);

            IpsiTotal    = IpsiCore + IpsiPeri + IpsiNormal;
            ContraTotal  = ContraCore + ContraPeri + ContraNormal;
            IP           = IpsiPeri - ContraPeri;
            IC           = IpsiCore - ContraCore;
            if IC < 0
                IC = 0;
            end 
            if IP < 0
                IP = 0;
            end

            % Edema ratio
            if (ContraTotal - IpsiNormal) ~= 0
                r = (IpsiTotal - ContraTotal) / (ContraNormal - IpsiNormal);
            else
                r = NaN;
                warning('Slice %s: r = 0', slicename);
            end
            
            % Edema correction
            if ~isnan(r) && r >= 0
                IC_corrected = IC / (1 + r);
                IP_corrected = IP / (1 + r);
            else
                IC_corrected = IC;
                IP_corrected = IP;
            end

            if IC_corrected < 0
                IC_corrected = 0;
            end 
            if IP_corrected < 0
                IP_corrected = 0;
            end
            
            % Severity
            Severity          = ((IP_corrected * IP_weight)+(IC_corrected * 1)) / ContraTotal * 100;
            NoEdemaCorrection = ((IP_corrected * 1)+(IC_corrected * 1)) / ContraTotal * 100;

            % Results
            % Result
            Severity_result{valid_count + 1, 1} = slicename;
            Severity_result{valid_count + 1, 2} = ContraTotal;
            Severity_result{valid_count + 1, 3} = ContraNormal;
            Severity_result{valid_count + 1, 4} = ContraPeri;
            Severity_result{valid_count + 1, 5} = ContraCore;
            Severity_result{valid_count + 1, 6} = IpsiTotal;
            Severity_result{valid_count + 1, 7} = IpsiNormal;
            Severity_result{valid_count + 1, 8} = IpsiPeri;
            Severity_result{valid_count + 1, 9} = IP;
            Severity_result{valid_count + 1, 10} = IP_corrected;
            Severity_result{valid_count + 1, 11} = IpsiCore;
            Severity_result{valid_count + 1, 12} = IC;
            Severity_result{valid_count + 1, 13} = IC_corrected;
            Severity_result{valid_count + 1, 14} = r;
            Severity_result{valid_count + 1, 15} = Severity;
            Severity_result{valid_count + 1, 16} = NoEdemaCorrection;
            
            valid_count = valid_count + 1;
            
            fprintf('  [%d/%d] %s: (Core=%d, Peri=%d, r=%.4f)\n', ...
                i, num_slices, slicename, IpsiCore, IpsiPeri, Severity);
            
        catch ME
            warning('Error: %s', slicename, ME.message);
            excluded_count = excluded_count + 1;
        end
    end
    
    if valid_count > 0
        Severity_result = Severity_result(1:valid_count, :);
    else
        Severity_result = {};
        warning('No avaliable data!');
    end

    fprintf('\n========== Severity finished ==========\n');
    fprintf('Total slice: %d\n', num_slices);
    fprintf('Success: %d\n', valid_count);
    fprintf('Excluded: %d\n', excluded_count);
end

%% RGB load
function RGB = loadRGB(base_name, suffix)
    % Multiple format
    formats_png = {
        [base_name, suffix, '.png'];          % "C7233_6 Contra.png"
        [base_name, strrep(suffix, ' ', ''), '.png'];  % "C7233_6Contra.png"
        [base_name, strrep(suffix, ' ', '_'), '.png'];  % "C7233_6_Contra.png"
    };
    
    for i = 1:length(formats_png)
        if exist(formats_png{i}, 'file')
            RGB = imread(formats_png{i});
            return;
        end
    end
    
    formats_jpg = {
        [base_name, suffix, '.jpg'];
        [base_name, strrep(suffix, ' ', ''), '.jpg'];
        [base_name, strrep(suffix, ' ', '_'), '.jpg'];
    };
    
    for i = 1:length(formats_jpg)
        if exist(formats_jpg{i}, 'file')
            RGB = imread(formats_jpg{i});
            return;
        end
    end
    
    error('No file：%s ', [base_name, suffix]);
end
