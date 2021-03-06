function [g2,par,b1,tvt,gap,g2_out,sig_out,tau_out] = tgv2_mri3d(mri_obj, par_in)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 
    tic
    %Set parameter#########################################################

    %(Slower) Debug mode
    debug = 1;

    %Stopping
    stop_rule = 'iteration';
    stop_par = 500;

    %TGV parameter
    alpha0 = sqrt(3);
    alpha1 = 1;
    
    %Pixel Spacing
    dx = 1;
    dy = 1;
    dz = 1;

    %Regularization parameter
    lambda = 5;            % Adapted automatically
    adapt_ld = 0;      % Adapt parameter according to given data
    steig = 0.223253;  % 
    dist = 5.581338;   % 

    %Stepsize
    sigma = 1/3;
    tau = 1/3;
    
    %Read parameter-------------------------------------------------------------------------
    %Input: par_in--------------------------------------------------------------------------
    %Generate list of parameters
    vars = whos;
    for l=1:size(vars,1)
        par_list{l,1} = vars(l).name;
    end
    %Set parameters according to list
    for l=1:size(par_in,1);
        valid = false;
        for j=1:size(par_list,1); if strcmp(par_in{l,1},par_list{j,1})
                valid = true;
                eval([par_in{l,1},'=','par_in{l,2}',';']);
            end; end
        if valid == false; warning(['Unexpected parameter at ',num2str(l)]); end
    end
    %---------------------------------------------------------------------------------------
    %---------------------------------------------------------------------------------------


    %Update parameter dependencies


    %Initialize###########################################

    %Set zero output
    b1=0;tvt=0;gap=0;g2_out=cell(1);sig_out=0;tau_out=0;

 
    % Setup Data and estimate sensitivities
    % mri_obj = prepare_data(mri_obj, {} );
   

    %Get size
    [ny,nx,nz,ncoils] = size(mri_obj.data);

    %Adapt regularization parameter
    if adapt_ld == 1
        subfac = (ny*nx*nz*ncoils)/sum(sum(sum(mri_obj.mask,3)));
        lambda = subfac*steig + dist;
        display(['Adapted ld(acceleration) to: ',num2str(lambda)]);
    end


    %Algorithmic##################################################################

    %Primal variable
    x = zeros(ny,nx,nz,4);
    x(:,:,:,1) =  mri_obj.u0;%backward_mri3d(mri_obj.data, mri_obj.b1, mri_obj.mask);
    


    %Extragradient
    ext = x;

    %Dual variable
    y = zeros(ny,nx,nz,9);	%Ordered as: (1) (2) (3)   (1,1) (2,2) (3,3) (1,2) (1,3) (2,3)
    z = zeros(ny,nx,nz,ncoils);

    %Finite difference operants
    [fDx,fDy,fDz] = get_sp_fdif(ny,nx,nz);
    [bDx,bDy,bDz] = get_sp_bdif(ny,nx,nz);


    %########################################################################################################
    if debug%Only in debug mode------------------------------------------------------------------------------
        factor = 1;
        if strcmp(stop_rule,'iteration');
            factor = 5;
            tvt = zeros(1, floor( stop_par/factor ) );
            gap = zeros(1, floor( stop_par/factor ) );
        elseif strcmp(stop_rule,'gap');
            tvt = zeros(1,1000);
            gap = zeros(1,1000);
        else
            error('Wrong stopping rule');
        end
        tvt(1) = get_tgv2(x,alpha0,alpha1,dx,dy,dz);
        gap(1) = abs( tvt(1) + gstar_tgv2_mri3d(x,y,z,mri_obj,dx,dy,dz,lambda) );
        gap(1) = gap(1)./(ny*nx*nz);
        enl = 1;

        sig_out = zeros(stop_par,1);
        tau_out = zeros(stop_par,1);

    end%------------------------------------------------------------------------------------------------------
    %########################################################################################################


    k=0;
    go_on = 1;
    while go_on

        %Dual ascent step (tested)
        y = y + sigma*cat(4,	sp_grad_3_1( ext(:,:,:,1), fDx,fDy,fDz,dx,dy,dz ) - ext(:,:,:,2:4)	,...
            sp_sym_grad_3_3( ext(:,:,:,2:4), bDx,bDy,bDz,dx,dy,dz )				);


        z = z + sigma*( forward_mri3d( ext(:,:,:,1),mri_obj.b1,mri_obj.mask ) );


        %Proximity maps
        n1 = norm_3( abs(y(:,:,:,1:3)) );
        n1 = max(1,n1./alpha1);
        for i=1:3
            y(:,:,:,i) = y(:,:,:,i)./n1;
        end
        n2 = norm_6( abs(y(:,:,:,4:9)) );
        n2 = max(1,n2./alpha0);
        for i=4:9
            y(:,:,:,i) = y(:,:,:,i)./n2;
        end

        z = (z-sigma*mri_obj.data ) / (1+sigma/lambda);

        %Primal descent step (tested)
        ext = x - tau*cat(4, -sp_div_3_3( y(:,:,:,1:3),fDx,fDy,fDz,dx,dy,dz ) + ...
                             backward_mri3d(z,mri_obj.b1,mri_obj.mask)		,...
            -y(:,:,:,1:3) - sp_div_3_6( y(:,:,:,4:9),bDx,bDy,bDz,dx,dy,dz )	);



        %Set extragradient
        x=2*ext - x;

        %Swap extragradient and primal variable
        [x,ext] = deal(ext,x);

        %Adapt stepsize
        if (k<10) || (rem(k,50) == 0) || debug
            [sigma,tau] = steps_tgv2_mri3d(ext-x,sigma,tau,mri_obj,dx,dy,dz);
            display(['adapted sig: ',num2str(sigma),' | tau: ',num2str(tau)]);
            sig_out(k+1) = sigma;
            tau_out(k+1) = tau;
        end

        %Increment iteration number
        k = k+1;

        if rem(k,10) == 0
            display(['Iteration:    ',num2str(k)]);
        end

        %Check stopping rule
        if ( strcmp(stop_rule,'iteration') && k>= stop_par )% || ( strcmp(stop_rule,'gap') && gap(1 + k/factor) < stop_par )
            go_on = 0;
        end


        %########################################################################################################
        if debug%Only in debug mode------------------------------------------------------------------------------
            %Enlarge tvt and gap
            if strcmp(stop_rule,'gap') && k>(1000*enl)
                tvt = [tvt,zeros(1,1000)]; gap = [gap,zeros(1,1000)]; enl = enl + 1;
            end

            if rem(k,factor) == 0
                tvt(1 + k/factor) = get_tgv2(x,alpha0,alpha1,dx,dy,dz);
                gap(1 + k/factor) = abs( tvt(1 + k/factor) + ...       
                              gstar_tgv2_mri3d(x, y, z, mri_obj, dx, dy, dz, lambda) );
                gap(1 + k/factor) = gap(1 + k/factor)./(ny*nx*nz);
            end

            if rem(k,250) == 0
                g2_out{k/10} = x(:,:,:,1);
            end
        end%------------------------------------------------------------------------------------------------------
        %########################################################################################################


    end

    display(['Sig:   ',num2str(sigma)])
    display(['Tau:   ',num2str(tau)])
    display(['Nr-it: ', num2str(k)])


    g2 =  x(:,:,:,1);
    
    g2 = image_shift3d(g2);


    %########################################################################################################
    if debug%Only in debug mode------------------------------------------------------------------------------
        %Crop back
        if strcmp(stop_rule,'gap')
            tvt = tvt(1:1+k);
            gap = gap(1:1+k);
        end

        %Output of b1 field
        b1 = mri_obj.b1;
    end%------------------------------------------------------------------------------------------------------
    %########################################################################################################

    eltime = toc;

    %Write parameter-------------------------------
    %Input: k (iteration number)-------------------
    psz = size(par_list,1);
    for l=1:psz
        par{l,1} = par_list{l,1};
        eval(['par{l,2} = ',par_list{l,1},';'])
    end
    par{psz+1,1} = 'iteration_nr'; par{psz+1,2}=k;
    par{psz+2,1} = mfilename;
    %Output: par-----------------------------------
    %----------------------------------------------


end