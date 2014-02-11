


%%
function [rtn, ts_err] = RSTA(paramsIn, dataIn)
    %% define global variables
    global loss_list;   % losses associated with different edge labelings
    global mu_list;     % marginal dual varibles: these are the parameters to be learned
    global E_list;      % edges of the Markov network e_i = [E(i,1),E(i,2)];
    global ind_edge_val_list;	% ind_edge_val{u} = [Ye == u] 
    global Ye_list;             % Denotes the edge-labelings 1 <-- [-1,-1], 2 <-- [-1,+1], 3 <-- [+1,-1], 4 <-- [+1,+1]
    global Kx_tr;   % X-kernel, assume to be positive semidefinite and normalized (Kx_tr(i,i) = 1)
    global Kx_ts;
    global Y_tr;    % Y-data: assumed to be class labels encoded {-1,+1}
    global Y_ts;
    global params;  % parameters use by the learning algorithm
    global m;       % number of training instances
    global l;       % number of labels
    global Kmu;     % Kx_tr*mu
    global primal_ub;
    global profile;
    global obj;
    global opt_round;
    global Rmu_list;
    global Smu_list;
    global T_size;
    global cc;
    global Kxx_mu_x_list;
    global Kxx_mu_x;
    
    %% initialize some of the global variables
    params=paramsIn;
    Kx_tr=dataIn.Kx_tr;
    Kx_ts=dataIn.Kx_ts;
    Y_tr=dataIn.Y_tr;
    Y_ts=dataIn.Y_ts;
    E_list=dataIn.Elist;
    l = size(Y_tr,2);
    m = size(Kx_tr,1);
    T_size = size(E_list,1);
    loss_list = cell(T_size, 1);
    Ye_list = cell(T_size, 1);
    ind_edge_val_list = cell(T_size, 1);
    Kxx_mu_x_list = cell(T_size, 1);
    cc = 1/size(E_list{1},1)/T_size;
    cc=1;
    mu_list = cell(T_size);
    for t=1:T_size
        [loss_list{t},Ye_list{t},ind_edge_val_list{t}] = compute_loss_vector(Y_tr,t,params.mlloss);
        mu_list{t} = zeros(4*size(E_list{1},1),m);
        Kxx_mu_x_list{t} = zeros(4*size(E_list{1},1),m);
    end


        
    %% initialization
    optimizer_init;
    profile_init;


    %% optimization
    print_message('Conditional gradient descend ...',0);
    primal_ub = Inf;
    opt_round = 0;
    compute_duality_gap;
    profile_update_tr;
   


    params.maxiter = 20;
       
    
    %% iterate until converge
    % parameters
    obj=0;
    prev_obj = 0;
    iter=0;
    kappa = 6; 
    nflip=Inf;
    params.verbosity = 2;
    progress_made = 1;
    profile.n_err_microlbl_prev=profile.n_err_microlbl;

    
    best_n_err_microlbl=Inf;
    best_iter = iter;
    best_mu_list=mu_list;
    best_Kxx_mu_x_list=Kxx_mu_x_list;
    best_Rmu_list=Rmu_list;
    best_Smu_list=Smu_list;
    % loop through examples
    while (primal_ub - obj >= params.epsilon*obj && ... % satisfy duality gap
            progress_made == 1 && ...                   % make progress
            nflip > 0 && ...                            % number of flips
            opt_round < params.maxiter ...              % within iteration limitation
            )
        opt_round = opt_round + 1;
        
        % iterate over examples 
        iter = iter +1;           
        for xi = 1:m
            print_message(sprintf('Start descend on example %d initial k %d',xi,kappa),3)
            [delta_obj] = optimize_x(xi,kappa,iter);    % optimize on single example
            obj = obj + delta_obj;  % updated objective
        end
        progress_made = (obj >= prev_obj);  
        prev_obj = obj;
        compute_duality_gap;        % duality gap
        profile_update_tr;          % profile update for training
        % update flip number
        if profile.n_err_microlbl > profile.n_err_microlbl_prev
            nflip = nflip - 1;
        end
        % update current best solution
        if profile.n_err_microlbl < best_n_err_microlbl
            best_n_err_microlbl=profile.n_err_microlbl;
            best_iter = iter;
            best_mu_list=mu_list;
            best_Kxx_mu_x_list=Kxx_mu_x_list;
            best_Rmu_list=Rmu_list;
            best_Smu_list=Smu_list;
        end

    end
    
    
    
    
    
    % last iteration
    iter = best_iter+1;
    mu_list = best_mu_list;
    Kxx_mu_x_list = best_Kxx_mu_x_list;
    Rmu_list = best_Rmu_list;
    Smu_list = best_Smu_list;
    for xi=1:m
        [delta_obj] = optimize_x(xi,kappa,iter);
        % TODO
        %profile_update_tr;
    end
    
    profile_update;
    
    

    rtn = 0;
    ts_err = 0;
end



% Complete gradient
function Kmu = compute_Kmu(Kx,t)
    global mu_list;
    global E_list;
    global ind_edge_val_list;
    mu = mu_list{t};
    ind_edge_val = ind_edge_val_list{t};
    E = E_list{t}; 
    

   
    m_oup = size(Kx,2);
    m = size(Kx,1);
    if  0 %and(params.debugging, nargin == 2)
        for x = 1:m
           Kmu(:,x) = compute_Kmu_x(x,Kx(:,x));
        end
        Kmu = reshape(Kmu,4,size(E,1)*m);
    else
        mu_siz = size(mu);
        mu = reshape(mu,4,size(E,1)*m);
        Smu = reshape(sum(mu),size(E,1),m);
        term12 =zeros(1,size(E,1)*m_oup);
        Kmu = zeros(4,size(E,1)*m_oup);
        for u = 1:4
            IndEVu = full(ind_edge_val{u});    
            Rmu_u = reshape(mu(u,:),size(E,1),m);
            H_u = Smu.*IndEVu;
            H_u = H_u - Rmu_u;
            Q_u = H_u*Kx;
            term12 = term12 + reshape(Q_u.*IndEVu,1,m_oup*size(E,1));
            Kmu(u,:) = reshape(-Q_u,1,m_oup*size(E,1));
        end
        for u = 1:4
            Kmu(u,:) = Kmu(u,:) + term12;
        end
    end
    %mu = reshape(mu,mu_siz);
    return
end


%%
% Input:
%   x,Kx,t
% Output
%   gradient for current example x
function Kmu_x = compute_Kmu_x(x,Kx,t)
    % global
    global E_list;
    global ind_edge_val_list;
    global Rmu_list;
    global Smu_list;
    % local
    m = size(Kx,1);
    term12 = zeros(1,size(E_list{t},1));
    term34 = zeros(4,size(E_list{t},1));
    
    % main
    % For speeding up gradient computations: 
    % store sums of marginal dual variables, distributed by the
    % true edge values into Smu
    % store marginal dual variables, distributed by the
    % pseudo edge values into Rmu
    if isempty(Rmu_list{t})
        Rmu_list{t} = cell(1,4);
        Smu_list{t} = cell(1,4);
        for u = 1:4
            Smu_list{t}{u} = zeros(size(E_list{t},1),m);
            Rmu_list{t}{u} = zeros(size(E_list{t},1),m);
        end
    end
    for u = 1:4
        Ind_te_u = full(ind_edge_val_list{t}{u}(:,x));
        H_u = Smu_list{t}{u}*Kx-Rmu_list{t}{u}*Kx;
        term12(1,Ind_te_u) = H_u(Ind_te_u)';
        term34(u,:) = -H_u';
    end
    Kmu_x = reshape(term12(ones(4,1),:) + term34,4*size(E_list{t},1),1);
end

%% compute relative duality gap
function compute_duality_gap

    global T_size;
    global Kx_tr;
    global loss_list;
    global E_list;
    global Y_tr;
    global params;
    global mu_list;
    global primal_ub;
    global obj;
    
    m=size(Kx_tr,1);
    Y=Y_tr;
    kappa=3;
    Ypred = zeros(size(Y));
    YpredVal = zeros(size(Y,1),1);
    Y_kappa = zeros(size(Y,1),size(Y,2)*kappa);
    Y_kappa_val = zeros(size(Y,1),kappa);
    
    %% compute current best label over trees
    % kappa best label
    for t=1:T_size
        loss = loss_list{t};
        E = E_list{t};
        loss = reshape(loss,4,size(E,1)*m);
        Kmu = compute_Kmu(Kx_tr,t);
        Kmu = reshape(Kmu,4,size(E,1)*m);
        gradient = loss - Kmu;
        [Y_kappa(((t-1)*size(Y,1)+1):(t*size(Y,1)),:),Y_kappa_val(((t-1)*size(Y,1)+1):(t*size(Y,1)),:)] = BestKDP(gradient,kappa);
    end
    % one single best label
    for i=1:size(Y,1)
        [Ypred(i,:),YpredVal(i,:)] = ...
            find_worst_violator(Y_kappa((i:size(Y_kappa,1)/T_size:size(Y_kappa,1)),:),Y_kappa_val((i:size(Y_kappa,1)/T_size:size(Y_kappa_val,1)),:));
    end
    % for initialization we assign - label
    if sum(sum(gradient))==0
        Ypred = Ypred * (-1);
    end
    %% duality gaps over trees
    dgap = zeros(1,T_size);
    for t=1:T_size
        loss = loss_list{t};
        E = E_list{t};
        mu = mu_list{t};
        loss = reshape(loss,4,size(E,1)*m);
        Kmu = compute_Kmu(Kx_tr,t);
        Kmu = reshape(Kmu,4,size(E,1)*m);
        gradient = loss - Kmu;
        Gmax = compute_Gmax(gradient,Ypred,t);
        mu = reshape(mu,4,m*size(E,1));
        duality_gap = params.C*max(Gmax,0) - sum(reshape(sum(gradient.*mu),size(E,1),m),1)';
        dgap(t) = sum(duality_gap);
    end
    %% primal upper bound
    primal_ub = obj + mean(dgap(t));
    
    return
end


%%  
function old_compute_duality_gap
    global E;
    global m;
    global params;
    global mu;
    global Kmu;
    global loss;
    global obj;
    global primal_ub;
    global duality_gap;
    global opt_round;
    l_siz = size(loss);
    loss = reshape(loss,4,size(E,1)*m);
    kmu_siz = size(Kmu);
    Kmu = reshape(Kmu,4,size(E,1)*m);
    gradient = loss - Kmu;
    mu_siz = size(mu);
    mu = reshape(mu,4,size(E,1)*m); gradient = reshape(gradient,4,size(E,1)*m);
    dgap = Inf; LBP_iter = 1;Gmax = -Inf;
    while LBP_iter <= size(E,1)
        LBP_iter = LBP_iter*2; % no of iterations = diameter of the graph
        if 1==1
            [~,~,G] = BestKDP(gradient); 
        else
            %[~,~,G] = max_gradient_labeling(gradient,LBP_iter); 
        end
        Gmax = max(Gmax,G);

        duality_gap = params.C*max(Gmax,0) - sum(reshape(sum(gradient.*mu),size(E,1),m),1)';
        dgap = sum(duality_gap);

        if obj+dgap < primal_ub+1E-6
            break;
        end
    end
    %primal_ub = min(obj+dgap,primal_ub);
    if primal_ub == Inf
         primal_ub = obj+dgap;
    else
         primal_ub = (obj+dgap)/min(opt_round,10)+primal_ub*(1-1/min(opt_round,10)); % averaging over a few last rounds
    end
    loss= reshape(loss,l_siz);
    Kmu = reshape(Kmu,kmu_siz);
    mu = reshape(mu,mu_siz);
end


%% conditional gradient optimization, conditional on example x
% input: 
%   x   --> the id of current training example
%   obj --> current objective
%   kappa --> current kappa
function [delta_obj] = optimize_x(x, kappa, iter)
    global loss_list;
    global loss;
    global Ye_list;
    global Ye;
    global E_list;
    global E;
    global mu_list;
    global mu;
    global ind_edge_val_list;
    global ind_edge_val;
    global Rmu_list;
    global Smu_list;
    global Kxx_mu_x_list;
    global cc;
    global l;
    global Kx_tr;
    global T_size;
    global params;
    

    
    
    %% collect top-K prediction from each tree
    print_message(sprintf('Collect top-k prediction from each tree T-size %d', T_size),3)
    Y_kappa = zeros(T_size,kappa*l);        % label prediction
    Y_kappa_val = zeros(T_size,kappa);      % score
    for t=1:T_size
        % variables located for tree t and example x
        loss = loss_list{t}(:,x);
        Ye = Ye_list{t}(:,x);
        ind_edge_val = ind_edge_val_list{t};
        mu = mu_list{t}(:,x);
        E = E_list{t};
        % compute the quantity for tree t
        Kmu_x = compute_Kmu_x(x,Kx_tr(:,x),t); % Kmu_x = K_x*mu_x
        gradient =  cc*loss - Kmu_x;    % current gradient
        % terminate if gradient is too small
        % TODO
        if norm(gradient) < params.tolerance
            break;
        end
        % find top k violator
        [Ymax,YmaxVal] = BestKDP(gradient,kappa);
        Y_kappa(t,:) = Ymax;
        Y_kappa_val(t,:) = YmaxVal;
    end
    
    
    %% get worst violator from top K
    print_message(sprintf('Get worst violator'),3)
    [Ymax, ~] = find_worst_violator(Y_kappa,Y_kappa_val);
    

    
    
    %% line serach
    mu_d_list = mu_list;
    print_message(sprintf('Line search'),3)
    nomi=zeros(1,T_size);
    denomi=zeros(1,T_size);
    kxx_mu_0 = cell(1,T_size);
    Gmax = zeros(1,T_size);
    G0 = zeros(1,T_size);
    Kmu_d_list = cell(1,T_size);
    for t=1:T_size
        % variables located for tree t and example x
        loss = loss_list{t}(:,x);
        Ye = Ye_list{t}(:,x);
        ind_edge_val = ind_edge_val_list{t};
        mu = mu_list{t}(:,x);
        E = E_list{t};

        %% compute
        Kmu_x = compute_Kmu_x(x,Kx_tr(:,x),t); % Kmu_x = K_x*mu_x
        gradient =  cc*loss - Kmu_x;
        Gmax(t) = compute_Gmax(gradient,Ymax,t);            % objective under best labeling
        G0(t) = -mu'*gradient;                               % current objective
        %% best margin violator into update direction mu_0
        Umax_e = 1+2*(Ymax(:,E(:,1))>0) + (Ymax(:,E(:,2)) >0);
        mu_0 = zeros(size(mu));
        for u = 1:4
            mu_0(4*(1:size(E,1))-4 + u) = params.C*(Umax_e == u);
        end
        % compute Kmu_0
        if sum(mu_0) > 0
            smu_1_te = sum(reshape(mu_0.*Ye,4,size(E,1)),1);
            smu_1_te = reshape(smu_1_te(ones(4,1),:),length(mu),1);
            kxx_mu_0{t} = ~Ye*params.C+mu_0-smu_1_te;
        else
            kxx_mu_0{t} = zeros(size(mu));
        end
        
        
        Kmu_0 = Kmu_x + kxx_mu_0{t} - Kxx_mu_x_list{t}(:,x);

        mu_d = mu_0 - mu;
        Kmu_d = Kmu_0-Kmu_x;
        
        
        Kmu_d_list{t} = Kmu_d;
        mu_d_list{t} = mu_d;
        nomi(t) = mu_d'*gradient;
        denomi(t) = Kmu_d' * mu_d;
        
    end
    
    % decide whether to update or not
    if sum(Gmax>=G0) == numel(G0)
        tau = min(sum(nomi)/sum(denomi),1);
        tau = 2/(2+iter);
        tau_list = min(nomi./denomi,1);
    else
        tau=0;
        tau_list = nomi*0;
    end
    
        
    if x==0 %
        [Gmax;G0;nomi;denomi;nomi./denomi;tau_list]'
    end
    


    %% update for each tree
	obj_list = zeros(1,T_size);
    delta_obj_list = zeros(1,T_size);
    %cur_obj_list = zeros(1,T_size);
    print_message(sprintf('Update for trees with Gmax %.2f G0 %.2f tao %.2f',Gmax,G0,tau),3)
    for t=1:T_size
        % variables located for tree t and example x
        loss = loss_list{t}(:,x);
        Ye = Ye_list{t}(:,x);
        ind_edge_val = ind_edge_val_list{t};
        mu = mu_list{t}(:,x);
        E = E_list{t};
        
        Kmu_x = compute_Kmu_x(x,Kx_tr(:,x),t); % Kmu_x = K_x*mu_x
        
        
        gradient =  cc*loss - Kmu_x;
        mu_d = mu_d_list{t};
        Kmu_d = Kmu_d_list{t};
        delta_obj_list(t) = gradient'*mu_d*tau - tau^2/2*mu_d'*Kmu_d;
        
        
        mu = mu + tau*mu_d;
        Kxx_mu_x_list{t}(:,x) = (1-tau)*Kxx_mu_x_list{t}(:,x) + tau*kxx_mu_0{t};
        % update Smu Rmu
        mu = reshape(mu,4,size(E,1));

        
        for u = 1:4
            Smu_list{t}{u}(:,x) = (sum(mu)').*ind_edge_val{u}(:,x);
            Rmu_list{t}{u}(:,x) = mu(u,:)';
        end
        
        
        
        

        mu = reshape(mu,4*size(E,1),1);
        mu_list{t}(:,x) = mu;
        
        

        
        %obj_list(t) = mu_list{t}(:)'*loss_list{t}(:) - (mu_list{t}(:)'*reshape(compute_Kmu(Kx_tr,t),4*size(E,1)*size(Kx_tr,1),1))/2
        %[cur_obj_list(t),delta_obj_list(t),obj_list(t)]
        
        
    end
    
    
    delta_obj =  sum(delta_obj_list);

    return
end

%%
% mu is marginal dual variable : 4|E| * m
% Kx is a column of x kernel : m * 1
% Kmu is part of the gradient : 4 * |E|
function Kmu = TODO_Calculate_Kmu(t,x,Kx,mu)
    % global
    global ind_edge_val_list;
    % local
    enum = size(mu,1)/4;
    ind_edge_val = ind_edge_val_list{t};
    m = size(Kx,1);
    term12 = zeros(1,enum);
    term34 = zeros(4,enum);
    Rmu = cell(1,4);
    Smu = cell(1,4);
    for u = 1:4
        Smu{u} = zeros(enum,m);
        Rmu{u} = zeros(enum,m);
    end
    
    % compute Rmu,Smu
    for i=1:m
        mu_x = mu(:,i);
        mu_x = reshape(mu_x,4,size(E,1));
        for u = 1:4
            Smu{u}(:,i) = (sum(mu_x)').*ind_edge_val{u}(:,i);
            Rmu{u}(:,i) = mu_x(u,:)';
        end
    end
    % compute Kmu
    for u = 1:4
        Ind_te_u = full(ind_edge_val{u}(:,x));
        H_u = Smu{u}*Kx-Rmu{u}*Kx;
        term12(1,Ind_te_u) = H_u(Ind_te_u)';
        term34(u,:) = -H_u';
    end
    Kmu = reshape(term12(ones(4,1),:) + term34, 4*enum, 1);    
end

%% 
function [Gmax] = compute_Gmax(gradient,Ymax,t)
    global E_list;
    
    m = size(Ymax,1);
    E = E_list{t};
    gradient = reshape(gradient,4,size(E,1)*m);
    Umax(1,:) = reshape(and(Ymax(:,E(:,1)) == -1,Ymax(:,E(:,2)) == -1)',1,size(E,1)*m);
    Umax(2,:) = reshape(and(Ymax(:,E(:,1)) == -1,Ymax(:,E(:,2)) == 1)',1,size(E,1)*m);
    Umax(3,:) = reshape(and(Ymax(:,E(:,1)) == 1,Ymax(:,E(:,2)) == -1)',1,size(E,1)*m);
    Umax(4,:) = reshape(and(Ymax(:,E(:,1)) == 1,Ymax(:,E(:,2)) == 1)',1,size(E,1)*m);
    % sum up the corresponding edge-gradients
    Gmax = reshape(sum(gradient.*Umax),size(E,1),m);
    Gmax = reshape(sum(Gmax,1),m,1);
end

%% get the worst margin violator from T*kappa violators
% Input: Y_kappa, Y_kappa_val
% Output:
function [Ymax, YmaxVal] = find_worst_violator(Y_kappa,Y_kappa_val)
    % global variable
    global l;
    % local variable
    Y_kappa_ind = Y_kappa_val * 0;
    Y_kappa = (Y_kappa+1)/2;
    % assing decimal value for each multilabel
    for i=1:size(Y_kappa_val,1)
        for j = 1:size(Y_kappa_val,2)
            Y_kappa_ind(i,j) = bi2de(Y_kappa(i,((j-1)*l+1):(j*l)));
        end
    end
    %
    for i=1:size(Y_kappa_val,2)
        t_line = sum(Y_kappa_val(:,i));
        current_matrix_val = Y_kappa_val(:,1:i);
        current_matrix_ind = Y_kappa_ind(:,1:i);
        unique_elements = unique(current_matrix_ind);
        element_id=0;
        element_val=-1;
        for j=1:size(unique_elements,1)
            current_val = sum(current_matrix_val(current_matrix_ind==unique_elements(j)));
            if current_val > element_val
                element_val = sum(current_matrix_val(current_matrix_ind==unique_elements(j)));
                element_id = unique_elements(j);                
            end
        end
        if element_val >= t_line
            break
        end
    end
    ind = find(Y_kappa_ind==element_id);
    ind = ind(1);
    i = ceil(mod(ind-1e-5, size(Y_kappa,1)));
    j = ceil((ind-1e-5) / size(Y_kappa,1));
    Ymax = Y_kappa(i,((j-1)*l+1):(j*l))*2-1;
    %YmaxInd = Y_kappa_ind(i,j);
    YmaxVal = Y_kappa_val(i,j);
    return
end



%% train profile and test profile update
function profile_update
    global params;
    global profile;
    global E;
    global Ye;
    global Y_tr;
    global Kx_tr;
    global Y_ts;
    global Kx_ts;
    global mu;
    global obj;
    global primal_ub;
    m = size(Ye,2);
    tm = cputime;
    print_message(sprintf('tm: %d  iter: %d obj: %f mu: max %f min %f dgap: %f',...
    round(tm-profile.start_time),profile.iter,obj,max(max(mu)),min(min(mu)),primal_ub-obj),5,sprintf('/var/tmp/%s.log',params.filestem));
    if params.profiling
        profile.next_profile_tm = profile.next_profile_tm + params.profile_tm_interval;
        profile.n_err_microlbl_prev = profile.n_err_microlbl;

        [Ypred_tr,~] = compute_error(Y_tr,Kx_tr);
        profile.microlabel_errors = sum(abs(Ypred_tr-Y_tr) >0,2);
        profile.n_err_microlbl = sum(profile.microlabel_errors);
        profile.p_err_microlbl = profile.n_err_microlbl/numel(Y_tr);
        profile.n_err = sum(profile.microlabel_errors > 0);
        profile.p_err = profile.n_err/length(profile.microlabel_errors);

        [Ypred_ts,Ypred_ts_val] = compute_error(Y_ts,Kx_ts);
        profile.microlabel_errors_ts = sum(abs(Ypred_ts-Y_ts) > 0,2);
        profile.n_err_microlbl_ts = sum(profile.microlabel_errors_ts);
        profile.p_err_microlbl_ts = profile.n_err_microlbl_ts/numel(Y_ts);
        profile.n_err_ts = sum(profile.microlabel_errors_ts > 0);
        profile.p_err_ts = profile.n_err_ts/length(profile.microlabel_errors_ts);

        print_message(...
            sprintf('tm: %d 1_er_tr: %d (%3.2f) er_tr: %d (%3.2f) 1_er_ts: %d (%3.2f) er_ts: %d (%3.2f)',...
        round(tm-profile.start_time),profile.n_err,profile.p_err*100,profile.n_err_microlbl,profile.p_err_microlbl*100,round(profile.p_err_ts*size(Y_ts,1)),profile.p_err_ts*100,sum(profile.microlabel_errors_ts),sum(profile.microlabel_errors_ts)/numel(Y_ts)*100),0,sprintf('/var/tmp/%s.log',params.filestem));
        %print_message(sprintf('%d here',profile.microlabel_errors_ts),4);

        running_time = tm-profile.start_time;
        sfile = sprintf('/var/tmp/Ypred_%s.mat',params.filestem);
        save(sfile,'Ypred_tr','Ypred_ts','params','Ypred_ts_val','running_time');
        Ye = reshape(Ye,4*size(E,1),m);
    end
end

%% training profile
function profile_update_tr
    global params;
    global profile;
    global Y_tr;
    global Kx_tr;
    global obj;
    global primal_ub;
    global mu;

    
    tm = cputime;
    
    print_message(...
        sprintf('tm: %d iter: %d obj: %.2f mu: max %.2f min %.2f dgap: %.2f',...
    round(tm-profile.start_time),profile.iter,obj,max(max(mu)),min(min(mu)),primal_ub-obj),...
    5,sprintf('/var/tmp/%s.log',params.filestem));

    if params.profiling
        profile.next_profile_tm = profile.next_profile_tm + params.profile_tm_interval;
        profile.n_err_microlbl_prev = profile.n_err_microlbl;
        % compute training error
        [Ypred_tr,~] = compute_error(Y_tr,Kx_tr);
        profile.microlabel_errors = sum(abs(Ypred_tr-Y_tr) >0,2);
        profile.n_err_microlbl = sum(profile.microlabel_errors);
        profile.p_err_microlbl = profile.n_err_microlbl/numel(Y_tr);
        profile.n_err = sum(profile.microlabel_errors > 0);
        profile.p_err = profile.n_err/length(profile.microlabel_errors);
        print_message(...
            sprintf('tm: %d 1_er_tr: %d (%3.2f) er_tr: %d (%3.2f) obj: %.2f gap: %.2f',...
            round(tm-profile.start_time),...
            profile.n_err,...
            profile.p_err*100,...
            profile.n_err_microlbl,...
            profile.p_err_microlbl*100,...
            obj,...
            primal_ub-obj),...
            0,sprintf('/var/tmp/%s.log',params.filestem));
    end
end

%% test error
function [Ypred,YpredVal] = compute_error(Y,Kx) 
    % global variable
    global T_size;
    global E_list;
    global E;
    % local variable
    kappa=3;
    Ypred = zeros(size(Y));
    YpredVal = zeros(size(Y,1),1);
    Y_kappa = zeros(size(Y,1),size(Y,2)*kappa);
    Y_kappa_val = zeros(size(Y,1),kappa);
    
    % main
    for t=1:T_size
        E = E_list{t};
        w_phi_e = compute_w_phi_e(Kx,t);
        [Y_kappa(((t-1)*size(Y,1)+1):(t*size(Y,1)),:),Y_kappa_val(((t-1)*size(Y,1)+1):(t*size(Y,1)),:)] = BestKDP(w_phi_e,kappa);
    end

    for i=1:size(Y,1)
        [Ypred(i,:),YpredVal(i,:)] = ...
            find_worst_violator(Y_kappa((i:size(Y_kappa,1)/T_size:size(Y_kappa,1)),:),Y_kappa_val((i:size(Y_kappa,1)/T_size:size(Y_kappa_val,1)),:));
    end
    % for initialization we assign - label
    if sum(sum(w_phi_e))==0
        Ypred = Ypred * (-1);
    end
    return
end


%% for testing
% Input: test kernel, tree index
% Output: gradient
function w_phi_e = compute_w_phi_e(Kx,t)
    % global variable
    global E_list;
    global Ye_list;
    global mu_list;
    global m;
    % local variables
    E = E_list{t};
    Ye = Ye_list{t};
    mu = mu_list{t};
    Ye = reshape(Ye,4,size(E,1)*m);   
    mu = reshape(mu,4,size(E,1)*m);
    m_oup = size(Kx,2);

    % main
    if isempty(find(mu,1))
        w_phi_e = zeros(4,size(E,1)*m_oup);
    else  
        w_phi_e = sum(mu);
        w_phi_e = w_phi_e(ones(4,1),:);
        w_phi_e = Ye.*w_phi_e;
        w_phi_e = w_phi_e-mu;
        w_phi_e = reshape(w_phi_e,4*size(E,1),m);
        w_phi_e = w_phi_e*Kx;
        w_phi_e = reshape(w_phi_e,4,size(E,1)*m_oup);
    end
end


%% linear time max sum
% calculate P(v) + \sum_{u\in chi(v)}M_{u->v}(v)
% time complexity is not O(K) now
% TODO better sorting algorithm with O(K)
function [res_sc,res_pt] = LinearMaxSum(data)
    %% parameters
    K = size(data,1); % top K
    max_nb_num = size(data,2); % maximum number of neighbor neighbors
    res_sc = zeros(K,1); % results that contain score
    res_pt = zeros(K,max_nb_num); % results that contain pointer value
    
    %% start from the first column
    cur_col = [(1:size(data,1))',data(:,1)]; % current column [index, score]
    cur_col = cur_col(cur_col(:,size(cur_col,2))~=0,:); % remove zero rows
    % if there is no score from tree below then return (meaning leave nodes)
    if numel(cur_col) == 0
        res_sc = zeros(size(data,1),1);
        res_pt = zeros(size(data,1),size(data,2));
        res_sc(1) = res_sc(1) + 1; 
        return
    end
    
    %% combine children score one at a time
    for i=2:max_nb_num
        next_col = [(1:size(data,1))',data(:,i)];
        next_col = next_col(next_col(:,size(next_col,2))~=0,:);
        % return if there is no leaves
        if numel(next_col)==0
            break
        end
        max_cur_row = min(size(cur_col,1),K);
        max_next_row = min(size(next_col,1),K);
        %res = [];
        res = zeros(max_cur_row*max_next_row,size(cur_col,2)+1);
        for p = 1:max_cur_row
            for q=1:max_next_row
                %res = [res;[cur_col(p,1:(size(cur_col,2)-1)),next_col(q,1),cur_col(p,size(cur_col,2))+next_col(q,2)]];
                res((p-1)*max_next_row+q,:) = [cur_col(p,1:(size(cur_col,2)-1)),next_col(q,1),cur_col(p,size(cur_col,2))+next_col(q,2)];
            end
        end
        res = sortrows(res,[-size(res,2)]);
        cur_col = res(1:min(K,size(res,1)),:);
    end
    
    %% collect results
    res_sc(1:size(cur_col,1),1) = cur_col(1:size(cur_col,1),size(cur_col,2)) + 1;
    res_pt(1:size(cur_col,1),1:(size(cur_col,2)-1)) = cur_col(1:size(cur_col,1),1:(size(cur_col,2)-1));
    return
end

%%


%% 
% dynamic programming fashion algorithm for top-K best inference
% assume rooted tree[par,chi;par,chi], score on edges
% get top k maximum score
% space complexity: 2*(K*|V|*max_degree)
% time complexity: 
function [Ymax,YmaxVal,Gmax] = BestKDP(gradient,K)


        
    %gradient = randsample(1:numel(gradient),numel(gradient));
    global E;
    
    if nargin < 2
        K=10;
    end

    %% 
    m = numel(gradient)/(4*size(E,1));
    nlabel = max(max(E));
    gradient = reshape(gradient,4,size(E,1)*m);
    min_gradient_val = min(min(gradient));
    gradient = gradient - min_gradient_val + 1e-5;
    node_degree = zeros(1,2);
    for i=1:nlabel
        node_degree(i) = sum(sum(E==i));
    end
    Ymax = zeros(m,nlabel*K);
    YmaxVal = zeros(m,K);
    if numel(gradient(gradient~=1)) == 0
            Ymax = Ymax +1;
            return
    end
    
    %% iteration throught examples
    for training_i = 1:m
        training_gradient = gradient(1:4,(training_i-1)*size(E,1)+1:(training_i*size(E,1)));
        if numel(training_gradient(training_gradient~=1)) == 0
            Ymax(training_i,:) = Ymax(training_i,:)+1;
            continue
        end        
        P_node = zeros(K*nlabel,2*max(node_degree)); % score matrix
        T_node = zeros(K*nlabel,2*max(node_degree)); % tracker matrix
        %% iterate on each edge from leave to node to propagation messages
        for i=size(E,1):-1:1
            if i==0
                break
            end

            p = E(i,1);
            c = E(i,2);
            %[training_i,i,p,c]
            % row block index for current edge (child, parent)
            row_block_chi_ind = ((c-1)*K+1):c*K;
            row_block_par_ind = ((p-1)*K+1):p*K;

            % update node score, calculate node top K list score P(v) + sum_{v'\in chi(v)}M_{v'->v}(v)
            col_block_ind = 3:2:size(P_node,2);
            [P_node(row_block_chi_ind,1),T_node(row_block_chi_ind,col_block_ind)] = LinearMaxSum(P_node(row_block_chi_ind,col_block_ind));
            [P_node(row_block_chi_ind,2),T_node(row_block_chi_ind,col_block_ind+1)] = LinearMaxSum(P_node(row_block_chi_ind,col_block_ind+1));

            % combine edge potential and send message to parent
            % S
            S_e = reshape(training_gradient(:,i),2,2);
            S_e = [repmat(S_e(1,:),K,1);repmat(S_e(2,:),K,1)];
            % M=S+P
            M = repmat(reshape(P_node(row_block_chi_ind,1:2),2*K,1),1,2);
            M = (M + S_e) .* (M & M);
            T = M;
            [u,v] = sort(M(:,1),'descend');
            M(:,1) = u;T(:,1) = v .* (u & u);
            [u,v] = sort(M(:,2),'descend');
            M(:,2) = u;T(:,2) = v .* (u & u);
            M = M(1:K,:);
            T = T(1:K,:);
            % put into correspond blocks
            j = sum(E(i:size(E,1),1) == p)+1;
            P_node(row_block_par_ind,(j-1)*2+1:j*2) = M;
            T_node(row_block_chi_ind,1:2) = T;
        end

        % one more iteration on root node
        row_block_chi_ind = ((p-1)*K+1):p*K;
        %disp([reshape(repmat(1:nlabel,K,1),nlabel*K,1),repmat([1:K]',nlabel,1),P_node])
        %disp([reshape(repmat(1:nlabel,K,1),nlabel*K,1),repmat([1:K]',nlabel,1),T_node])
        % update node score, calculate node top K list score P(v) + sum_{v'\in chi(v)}M_{v'->v}(v)
        col_block_ind = 3:2:size(P_node,2);
        [P_node(row_block_chi_ind,1),T_node(row_block_chi_ind,col_block_ind)] = LinearMaxSum(P_node(row_block_chi_ind,col_block_ind));
        [P_node(row_block_chi_ind,2),T_node(row_block_chi_ind,col_block_ind+1)] = LinearMaxSum(P_node(row_block_chi_ind,col_block_ind+1));
        T_node(row_block_chi_ind,1:2) = [1:K;(1:K)+K]';

        %disp([reshape(repmat(1:nlabel,K,1),nlabel*K,1),repmat([1:K]',nlabel,1),P_node])
        %disp([reshape(repmat(1:nlabel,K,1),nlabel*K,1),repmat([1:K]',nlabel,1),T_node])


        %% trace back
        node_degree(E(1,1)) = node_degree(E(1,1))+1;

        % root node
        for k=1:K
            if k==0
                break
            end
            % k'th best multilabel
            Y=zeros(nlabel,1);

            Q_node = P_node;
            zero_mask = zeros(K,2);

            % pick up the k'th best value from root
            p = E(1,1);
            row_block_par_ind = ((p-1)*K+1):p*K;
            [~,v] = sort(reshape(P_node(row_block_par_ind,1:2),2*K,1),'descend');
            col_pos = ceil((v(k)-1e-5)/K);
            row_pos = ceil(mod(v(k)-1e-5,K));
            YmaxVal(training_i,k) = P_node(row_pos,col_pos);
            zero_mask(row_pos,col_pos) = 1;
            Q_node(row_block_par_ind,1:2) = Q_node(row_block_par_ind,1:2) .* zero_mask;
            zero_mask(row_pos,col_pos) = 0;

            % now everthing is standardized, then we do loop
            p=0;
            for i=1:size(E,1)
                if p == E(i,1)
                    continue
                end
                p = E(i,1);
                c = E(i,2);
                %[i,p,c]
                % get block of the score matrix
                row_block_par_ind = ((p-1)*K+1):p*K;
                % get current optimal score position
                if m==1
                %[reshape(repmat(1:nlabel,K,1),nlabel*K,1),repmat([1:K]',nlabel,1),T_node]
                %[reshape(repmat(1:nlabel,K,1),nlabel*K,1),repmat([1:K]',nlabel,1),Q_node]
                end
                index = find(Q_node(row_block_par_ind,1:2)~=0);
                col_pos = ceil((index-1e-5)/K);
                row_pos = ceil(mod(index-1e-5,K));
                
                %[index,col_pos,row_pos]
                % emit a label
                T_par_block = T_node(row_block_par_ind,1:2);
                Y(p) = ceil((T_par_block(row_pos, col_pos)-1e-5)/K);
                % number of children
                n_chi = node_degree(p)-1;
                %disp(sprintf('%d->%d, n_chi %d, index %d -->(%d,%d)', p,c,n_chi,index,row_pos,col_pos))
                % children in order
                cs = zeros(n_chi,1);
                j=0;
                while E(i+j,1)==p
                    %[i,j,E(i+j,1),i+j,size(E,1),j+1]
                    cs(j+1) = E(i+j,2);
                    j=j+1;
                    if i+j>size(E,1)
                        break;
                    end
                end     
                % loop through children
                for j=size(cs,1):-1:1
                    c = cs(j);
                    %disp(sprintf('%d->%d',p,c))
                    c_pos = (n_chi-j+2);
                    col_block_c_ind = ((c_pos-1)*2+1):c_pos*2;
                    block = T_node(row_block_par_ind,col_block_c_ind);
                    index = block(row_pos,col_pos) + (col_pos-1)*K;
                    c_col_pos = ceil((index-1e-5)/K);
                    c_row_pos = ceil(mod(index-1e-5,K));
                    row_block_c_ind = ((c-1)*K+1):c*K;
                    T_chi_block = T_node(row_block_c_ind,1:2);
                    c_index = T_chi_block(c_row_pos,c_col_pos);
                    cc_col_pos = ceil((c_index-1e-5)/K);
                    cc_row_pos = ceil(mod(c_index-1e-5,K));
                    %disp(sprintf('chi index %d -->(%d,%d) %d -->(%d,%d)',index,c_row_pos,c_col_pos,c_index,cc_row_pos,cc_col_pos))
                    zero_mask(cc_row_pos,cc_col_pos) = 1;
                    Q_node(row_block_c_ind,1:2) = Q_node(row_block_c_ind,1:2) .* zero_mask;
                    zero_mask(cc_row_pos,cc_col_pos) = 0;
                    % leave node: emit directly
                    if node_degree(c) == 1
                        Y(c) = cc_col_pos;
                    end
                end
            end
            Ymax(training_i,(k-1)*nlabel+1:k*nlabel) = Y'*2-3;
        end
        node_degree(E(1,1)) = node_degree(E(1,1))-1;
    end
    %%
    if nargout > 2
        % find out the max gradient for each example: pick out the edge labelings
        % consistent with Ymax
        Ymax_1 = Ymax(:,1:nlabel);
        Umax(1,:) = reshape(and(Ymax_1(:,E(:,1)) == -1,Ymax_1(:,E(:,2)) == -1)',1,size(E,1)*m);
        Umax(2,:) = reshape(and(Ymax_1(:,E(:,1)) == -1,Ymax_1(:,E(:,2)) == 1)',1,size(E,1)*m);
        Umax(3,:) = reshape(and(Ymax_1(:,E(:,1)) == 1,Ymax_1(:,E(:,2)) == -1)',1,size(E,1)*m);
        Umax(4,:) = reshape(and(Ymax_1(:,E(:,1)) == 1,Ymax_1(:,E(:,2)) == 1)',1,size(E,1)*m);
        % sum up the corresponding edge-gradients
        Gmax = reshape(sum(gradient.*Umax),size(E,1),m);
        Gmax = reshape(sum(Gmax,1),m,1);
    end
    return
end



%%
function [loss,Ye,ind_edge_val] = compute_loss_vector(Y,t,scaling)
    % scaling: 0=do nothing, 1=rescale node loss by degree
    global E_list;
    global m;
    ind_edge_val = cell(4,1);
    print_message(sprintf('Computing loss vector for %d_th Tree.',t),0);
    E = E_list{t};
    loss = ones(4,m*size(E,1));
    Te1 = Y(:,E(:,1))'; % the label of edge tail
    Te2 = Y(:,E(:,2))'; % the label of edge head
    NodeDegree = ones(size(Y,2),1);
    if scaling ~= 0 % rescale to microlabels by dividing node loss among the adjacent edges
        for v = 1:size(Y,2)
            NodeDegree(v) = sum(E(:) == v);
        end
    end
    NodeDegree = repmat(NodeDegree,1,m);    
    u = 0;
    for u_1 = [-1, 1]
        for u_2 = [-1, 1]
            u = u + 1;
            loss(u,:) = reshape((Te1 ~= u_1).*NodeDegree(E(:,1),:)+(Te2 ~= u_2).*NodeDegree(E(:,2),:),m*size(E,1),1);
        end
    end    
    loss = reshape(loss,4*size(E,1),m);
   
    Ye = reshape(loss==0,4,size(E,1)*m);
    for u = 1:4
        ind_edge_val{u} = sparse(reshape(Ye(u,:)~=0,size(E,1),m));
    end
    Ye = reshape(Ye,4*size(E,1),m);
    %loss = loss*0+1;
    return
end

%%
function profile_init
    global profile;
    profile.start_time = cputime;
    profile.next_profile_tm = profile.start_time;
    profile.n_err = 0;
    profile.p_err = 0; 
    profile.n_err_microlbl = 0; 
    profile.p_err_microlbl = 0; 
    profile.n_err_microlbl_prev = 0;
    profile.microlabel_errors = [];
    profile.iter = 0;
    profile.err_ts = 0;
end

%%
function optimizer_init
    global T_size;
    global Rmu_list;
    global Smu_list;
    global obj;
    global delta_obj;
    global opt_round;
    
    Rmu_list = cell(T_size,1);
    Smu_list = cell(T_size,1);
    obj=0;
    delta_obj=0;
    opt_round=0;
end

%%
function print_message(msg,verbosity_level,filename)
    global params;
    if params.verbosity >= verbosity_level
        fprintf('%s: %s\n',datestr(clock,13),msg);
        if nargin == 3
            fid = fopen(filename,'a');
            fprintf(fid,'%s: %s\n',datestr(clock,13),msg);
            fclose(fid);
        end
    end
end

